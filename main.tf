data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}



data "aws_iam_policy_document" "ec2_policy_document" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

locals {
  common_tags = {
    Project     = "MySQL-Terraform"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }

  instance_tags = merge(local.common_tags, {
    Name = var.instance_name
  })

  security_group_tags = merge(local.common_tags, {
    Name = "ec2-security group"
  })

  iam_role_tags = merge(local.common_tags, {
    Name = "ec2-iam-role"
  })

  vpc_tags = merge(local.common_tags, {
    Name = "mysql-production-vpc"
  })

  igw_tags = merge(local.common_tags, {
    Name = "internet-gateway"
  })

  private_subnet_tags = merge(local.common_tags, {
    Name = var.mysql_private_subnet
    Tier = "Private"
  })

  private_route_table_tags = merge(local.common_tags, {
    Name = "mysql-private-subnet-route-table"
    Tier = "Private"
  })

  vpc_endpoint_sg_tags = merge(local.common_tags, {
    Name    = " vpc-endpoint-security-group"
    Purpose = "Allow private subnet to reach VPC endpoints"
  })

  ssm_endpoint_tags = merge(local.common_tags, {
    Name    = "ssm-endpoint"
    Service = "Systems Manager"
  })

  ssm_messages_endpoint_tags = merge(local.common_tags, {
    Name    = "ssm-messages-endpoint"
    Service = "Systems Manager Messages"
  })

  ec2_messages_endpoint_tags = merge(local.common_tags, {
    Name    = "ec2-messages-endpoint"
    Service = "EC2 Messages"
  })
}

# Create a Custom VPC
resource "aws_vpc" "ec2_vpc" {
  cidr_block           = var.vpc_cidr
  tags                 = local.vpc_tags
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create a Security Group
resource "aws_security_group" "allow_tls" {
  name   = "EC2 Security Group"
  vpc_id = aws_vpc.ec2_vpc.id
  tags   = local.security_group_tags
}

# Create Egress Rule
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}



# Create EC2 Instance
resource "aws_instance" "mysql_ec2_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = local.instance_tags
}

# Create IAM Role for EC2
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-iam-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_policy_document.json

  tags = local.iam_role_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create Instance Profile
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "ec2_ssm_instance_profile"
  role = aws_iam_role.ec2_ssm_role.name

  depends_on = [
    aws_iam_role_policy_attachment.ssm
  ]
}

# Create Internet Gateway
resource "aws_internet_gateway" "mysql_igw" {
  vpc_id = aws_vpc.ec2_vpc.id

  tags = local.igw_tags
}

# Create Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.ec2_vpc.id
  cidr_block              = var.mysql_private_subnet
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = local.private_subnet_tags
}

# Create Route Table
resource "aws_route_table" "mysql_route_table" {
  vpc_id = aws_vpc.ec2_vpc.id
  tags   = local.private_route_table_tags
}

# Create Route Table Association
resource "aws_route_table_association" "mysql_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.mysql_route_table.id
}

# Create a Route
resource "aws_route" "mysql_route" {
  count                  = var.enable_internet_access ? 1 : 0
  route_table_id         = aws_route_table.mysql_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mysql_igw.id
}

# Create a security group for VPC endpoint
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.ec2_vpc.id

  tags = local.vpc_endpoint_sg_tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.vpc_endpoints_sg.id
  cidr_ipv4         = var.mysql_private_subnet
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

# Create SSM VPC Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.ec2_vpc.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = local.ssm_endpoint_tags
}

# Create SSM Messages VPC Endpoint
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.ec2_vpc.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = local.ssm_messages_endpoint_tags
}

# Create EC2 Messages VPC Endpoint
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.ec2_vpc.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = local.ec2_messages_endpoint_tags
}