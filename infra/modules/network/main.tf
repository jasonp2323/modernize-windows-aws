##############################################################################
# VPC with four tiers:
#   public  - NAT gateways and (optionally) an RDP bastion
#   app     - domain-joined application servers, management server
#   data    - AWS Managed Microsoft AD, FSx for Windows File Server, RDS
#   stream  - WorkSpaces Applications (AppStream 2.0) fleet ENIs
##############################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /24s carved out of the VPC CIDR, one block of offsets per tier.
  tier_offsets = {
    public = 0
    app    = 10
    data   = 20
    stream = 30
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

##############################################################################
# Subnets
##############################################################################

resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, var.subnet_newbits, local.tier_offsets.public + each.value)
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "app" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, local.tier_offsets.app + each.value)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-${each.key}"
    Tier = "app"
  })
}

resource "aws_subnet" "data" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, local.tier_offsets.data + each.value)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-data-${each.key}"
    Tier = "data"
  })
}

resource "aws_subnet" "stream" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, local.tier_offsets.stream + each.value)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-stream-${each.key}"
    Tier = "stream"
  })
}

##############################################################################
# NAT
#
# Domain-joined Windows instances and AppStream fleets need outbound internet
# for Windows Update, the SSM agent, FSLogix/agent downloads and (when Entra ID
# is in play) outbound HTTPS to Microsoft Entra.
##############################################################################

locals {
  nat_azs = var.enable_nat_gateway ? (var.single_nat_gateway ? [local.azs[0]] : local.azs) : []
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

##############################################################################
# Routing
##############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = toset(local.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-private-${each.key}" })
}

resource "aws_route" "private_default" {
  for_each = var.enable_nat_gateway ? toset(local.azs) : toset([])

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[local.azs[0]].id : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "stream" {
  for_each = aws_subnet.stream

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
