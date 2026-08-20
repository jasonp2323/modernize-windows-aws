##############################################################################
# Amazon WorkSpaces Applications (formerly AppStream 2.0)
#
# Two delivery models from one directory and one FSLogix profile store:
#
#   app fleet     - stream_view = APP. Publishes a single application; the user
#                   sees only that window, RemoteApp style.
#   desktop fleet - stream_view = DESKTOP. Non-persistent Windows desktops.
#
# Both fleets are domain joined, which means:
#   * user identity comes from SAML federation (Entra ID here), not the
#     AppStream user pool;
#   * FSLogix on the image mounts each user's profile container from the
#     dedicated FSx file system;
#   * fleet instances create computer objects in the streaming OUs, which the
#     directory service account is delegated rights over.
##############################################################################

resource "aws_security_group" "fleet" {
  name        = "${var.name_prefix}-stream"
  description = "WorkSpaces Applications fleet and image builder ENIs"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-stream" })
}

resource "aws_vpc_security_group_egress_rule" "fleet_all" {
  security_group_id = aws_security_group.fleet.id
  description       = "All egress - domain controllers, FSx, application tier, internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

##############################################################################
# Directory configuration
#
# The service account listed here is the one the management automation created
# and delegated computer-object rights to.
##############################################################################

resource "aws_appstream_directory_config" "this" {
  # Registered only when something needs it. AppStream validates the service
  # account credentials on create, and that account is created by the domain
  # automation - so this must not run during the first stage.
  count = var.enable_directory_config ? 1 : 0

  directory_name                          = var.directory_name
  organizational_unit_distinguished_names = var.organizational_unit_distinguished_names

  service_account_credentials {
    account_name     = var.service_account_name
    account_password = var.service_account_password
  }
}

##############################################################################
# Image builders
#
# Created on demand: you build an image once, note its name, and can then turn
# the builders off. They are not part of the steady-state environment.
##############################################################################

resource "aws_appstream_image_builder" "this" {
  for_each = var.enable_image_builders ? var.image_builders : {}

  name                           = "${var.name_prefix}-${each.key}"
  display_name                   = each.value.display_name
  description                    = each.value.description
  image_name                     = var.base_image_name
  instance_type                  = each.value.instance_type
  enable_default_internet_access = false

  vpc_config {
    subnet_ids         = [var.subnet_ids[0]]
    security_group_ids = [aws_security_group.fleet.id]
  }

  domain_join_info {
    directory_name                         = var.directory_name
    organizational_unit_distinguished_name = each.value.organizational_unit_distinguished_name
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  lifecycle {
    precondition {
      condition     = var.base_image_name != null
      error_message = "Set appstream_base_image_name. List the public base images with: aws appstream describe-images --type PUBLIC --query \"Images[?starts_with(Name, 'AppStream-WinServer')].Name\"."
    }
  }

  depends_on = [aws_appstream_directory_config.this]
}

##############################################################################
# Fleets
##############################################################################

resource "aws_appstream_fleet" "this" {
  for_each = var.enable_fleets ? var.fleets : {}

  name         = "${var.name_prefix}-${each.key}"
  display_name = each.value.display_name
  description  = each.value.description

  image_name    = each.value.image_name
  instance_type = each.value.instance_type
  fleet_type    = each.value.fleet_type
  stream_view   = each.value.stream_view

  max_user_duration_in_seconds       = each.value.max_user_duration_in_seconds
  disconnect_timeout_in_seconds      = each.value.disconnect_timeout_in_seconds
  idle_disconnect_timeout_in_seconds = each.value.idle_disconnect_timeout_in_seconds
  enable_default_internet_access     = false

  compute_capacity {
    desired_instances = each.value.desired_instances
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.fleet.id]
  }

  domain_join_info {
    directory_name                         = var.directory_name
    organizational_unit_distinguished_name = each.value.organizational_unit_distinguished_name
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  lifecycle {
    precondition {
      condition     = each.value.image_name != null
      error_message = "Each enabled fleet needs the name of an image you built with Image Assistant."
    }
  }

  depends_on = [aws_appstream_directory_config.this]
}

##############################################################################
# Stacks
#
# Application settings persistence is deliberately disabled: FSLogix owns the
# whole profile, and running both leads to two sources of truth for user state.
##############################################################################

resource "aws_appstream_stack" "this" {
  for_each = var.enable_fleets ? var.fleets : {}

  name         = "${var.name_prefix}-${each.key}"
  display_name = each.value.display_name
  description  = each.value.description

  application_settings {
    enabled = false
  }

  dynamic "user_settings" {
    for_each = var.user_settings

    content {
      action     = user_settings.key
      permission = user_settings.value
    }
  }

  streaming_experience_settings {
    preferred_protocol = "TCP"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

resource "aws_appstream_fleet_stack_association" "this" {
  for_each = var.enable_fleets ? var.fleets : {}

  fleet_name = aws_appstream_fleet.this[each.key].name
  stack_name = aws_appstream_stack.this[each.key].name
}

##############################################################################
# Optional fleet auto scaling
##############################################################################

resource "aws_appautoscaling_target" "fleet" {
  for_each = var.enable_fleets && var.enable_autoscaling ? var.fleets : {}

  service_namespace  = "appstream"
  resource_id        = "fleet/${aws_appstream_fleet.this[each.key].name}"
  scalable_dimension = "appstream:fleet:DesiredCapacity"
  min_capacity       = each.value.min_capacity
  max_capacity       = each.value.max_capacity
}

resource "aws_appautoscaling_policy" "fleet" {
  for_each = var.enable_fleets && var.enable_autoscaling ? var.fleets : {}

  name               = "${var.name_prefix}-${each.key}-utilization"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.fleet[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.fleet[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.fleet[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_target_utilization
    scale_in_cooldown  = 360
    scale_out_cooldown = 120

    predefined_metric_specification {
      predefined_metric_type = "AppStreamAverageCapacityUtilization"
    }
  }
}
