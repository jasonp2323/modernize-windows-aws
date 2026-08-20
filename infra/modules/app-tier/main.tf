##############################################################################
# Application tier
#
# Domain-joined Windows application servers behind an internal load balancer.
# The streaming fleets and the management server are the only clients; nothing
# here is reachable from the internet.
##############################################################################

data "aws_ssm_parameter" "windows_ami" {
  name = var.windows_ami_ssm_parameter
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "Windows application servers"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-app" })
}

resource "aws_security_group" "alb" {
  count = var.create_load_balancer ? 1 : 0

  name        = "${var.name_prefix}-app-alb"
  description = "Internal load balancer for the application tier"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-alb" })
}

locals {
  # Who may reach the application over HTTP(S): the streaming fleets, the
  # management tier, and the load balancer when there is one.
  app_client_cidrs = var.client_cidrs
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each = toset(local.app_client_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTP from streaming and management tiers"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  for_each = toset(local.app_client_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTPS from streaming and management tiers"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_rdp" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "RDP for administration"
  cidr_ipv4         = each.value
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  count = var.create_load_balancer ? 1 : 0

  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the internal load balancer"
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = var.create_load_balancer ? toset(local.app_client_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from streaming and management tiers"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  count = var.create_load_balancer ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

##############################################################################
# Servers
##############################################################################

resource "aws_instance" "app" {
  count = var.instance_count

  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, var.domain_join_tags, {
    Name    = format("%s-app-%02d", var.name_prefix, count.index + 1)
    Role    = "application"
    AppTier = var.name_prefix
  })

  volume_tags = merge(var.tags, {
    Name = format("%s-app-%02d", var.name_prefix, count.index + 1)
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

##############################################################################
# Internal load balancer
##############################################################################

resource "aws_lb" "app" {
  count = var.create_load_balancer ? 1 : 0

  name               = "${var.name_prefix}-app"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb[0].id]

  tags = merge(var.tags, { Name = "${var.name_prefix}-app" })
}

resource "aws_lb_target_group" "app" {
  count = var.create_load_balancer ? 1 : 0

  name     = "${var.name_prefix}-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app" })
}

resource "aws_lb_target_group_attachment" "app" {
  count = var.create_load_balancer ? var.instance_count : 0

  target_group_arn = aws_lb_target_group.app[0].arn
  target_id        = aws_instance.app[count.index].id
  port             = 80
}

resource "aws_lb_listener" "app" {
  count = var.create_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}

##############################################################################
# Application role configuration
#
# Installs IIS and a page that proves the instance is domain joined and can
# reach SQL Server. Replace with your real application deployment.
##############################################################################

resource "aws_ssm_document" "configure_app" {
  name            = "${var.name_prefix}-configure-app-server"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Installs the web role and a diagnostic page on the application servers."
    parameters = {
      SqlEndpoint = { type = "String", description = "RDS SQL Server endpoint.", default = "not-configured" }
    }
    mainSteps = [{
      action = "aws:runPowerShellScript"
      name   = "configureApplicationRole"
      inputs = {
        timeoutSeconds = "1800"
        runCommand = [
          "$ErrorActionPreference = 'Stop'",
          "Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console -IncludeManagementTools | Out-Null",
          "$cs = Get-CimInstance Win32_ComputerSystem",
          "$html = \"<html><body style='font-family:Segoe UI'><h1>$($cs.Name)</h1><p>Domain: $($cs.Domain)</p><p>Joined: $($cs.PartOfDomain)</p><p>SQL endpoint: {{SqlEndpoint}}</p></body></html>\"",
          "Set-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value $html -Encoding UTF8",
          "Remove-Item -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Force -ErrorAction SilentlyContinue",
        ]
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-configure-app-server" })
}

resource "aws_ssm_association" "configure_app" {
  count = var.instance_count > 0 ? 1 : 0

  name             = aws_ssm_document.configure_app.name
  association_name = "${var.name_prefix}-configure-app-servers"

  parameters = {
    SqlEndpoint = var.sql_endpoint
  }

  targets {
    key    = "tag:AppTier"
    values = [var.name_prefix]
  }
}
