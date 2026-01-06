data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
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
    Name      = var.instance_name
    Component = "Compute"
    Service   = "MySQL Database Server"
    Tier      = "Private"
  })

  security_group_tags = merge(local.common_tags, {
    Name      = "ec2-security-group"
    Component = "Security"
    Service   = "EC2 Instance Firewall"
    Purpose   = "Allow outbound traffic from EC2"
  })

  iam_role_tags = merge(local.common_tags, {
    Name      = "ec2-iam-role"
    Component = "Security"
    Service   = "IAM Role"
    Purpose   = "Enable Systems Manager access for EC2"
  })

  vpc_tags = merge(local.common_tags, {
    Name      = "mysql-production-vpc"
    Component = "Networking"
    Service   = "VPC"
    CIDR      = var.vpc_cidr
  })

  igw_tags = merge(local.common_tags, {
    Name      = "mysql-internet-gateway"
    Component = "Networking"
    Service   = "Internet Gateway"
    Purpose   = "Provide internet access for NAT Gateway"
  })

  private_subnet_tags = merge(local.common_tags, {
    Name      = "mysql-private-subnet"
    Component = "Networking"
    Service   = "Subnet"
    Tier      = "Private"
    CIDR      = var.private_subnet_cidr
    Purpose   = "Host MySQL EC2 instance without public exposure"
  })

  public_subnet_tags = merge(local.common_tags, {
    Name      = "mysql-public-subnet"
    Component = "Networking"
    Service   = "Subnet"
    Tier      = "Public"
    CIDR      = var.public_subnet_cidr
    Purpose   = "Host NAT Gateway for outbound internet access"
  })

  private_route_table_tags = merge(local.common_tags, {
    Name      = "mysql-private-route-table"
    Component = "Networking"
    Service   = "Route Table"
    Tier      = "Private"
    Purpose   = "Route private subnet traffic to NAT Gateway when enabled"
  })

  public_route_table_tags = merge(local.common_tags, {
    Name      = "mysql-public-route-table"
    Component = "Networking"
    Service   = "Route Table"
    Tier      = "Public"
    Purpose   = "Route public subnet traffic to Internet Gateway"
  })

  vpc_endpoint_sg_tags = merge(local.common_tags, {
    Name      = "vpc-endpoint-security-group"
    Component = "Security"
    Service   = "VPC Endpoint Firewall"
    Purpose   = "Allow HTTPS traffic from private subnet to VPC endpoints"
  })

  ssm_endpoint_tags = merge(local.common_tags, {
    Name      = "ssm-endpoint"
    Component = "Networking"
    Service   = "VPC Endpoint - Systems Manager"
    Type      = "Interface"
    Purpose   = "Private connection to AWS Systems Manager API"
  })

  ssm_messages_endpoint_tags = merge(local.common_tags, {
    Name      = "ssm-messages-endpoint"
    Component = "Networking"
    Service   = "VPC Endpoint - SSM Messages"
    Type      = "Interface"
    Purpose   = "Private connection for Session Manager data streaming"
  })

  ec2_messages_endpoint_tags = merge(local.common_tags, {
    Name      = "ec2-messages-endpoint"
    Component = "Networking"
    Service   = "VPC Endpoint - EC2 Messages"
    Type      = "Interface"
    Purpose   = "Private connection for EC2 instance registration"
  })

  nat_eip_tags = merge(local.common_tags, {
    Name      = "mysql-nat-eip"
    Component = "Networking"
    Service   = "Elastic IP"
    Purpose   = "Static public IP for NAT Gateway"
    Lifecycle = "Conditional - Only exists when internet access enabled"
  })

  nat_gateway_tags = merge(local.common_tags, {
    Name      = "mysql-nat-gateway"
    Component = "Networking"
    Service   = "NAT Gateway"
    Purpose   = "Enable conditional outbound internet for private subnet"
    CostOptimization = "Created on-demand to minimize costs"
    Lifecycle = "Conditional - Only exists when internet access enabled"
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
resource "aws_instance" "ec2_instance" {
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
resource "aws_internet_gateway" "ec2_igw" {
  vpc_id = aws_vpc.ec2_vpc.id

  tags = local.igw_tags
}

# Create Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.ec2_vpc.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = local.private_subnet_tags
}

# Create Public Subnet (for NAT Gateway)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.ec2_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = local.public_subnet_tags
}

# Create Route Table
resource "aws_route_table" "ec2_route_table" {
  vpc_id = aws_vpc.ec2_vpc.id
  tags   = local.private_route_table_tags
}

# Create Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.ec2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ec2_igw.id
  }

  tags = local.public_route_table_tags
}

# Create Route Table Association
resource "aws_route_table_association" "ec2_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.ec2_route_table.id
}

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Elastic IP for NAT Gateway (conditional)
resource "aws_eip" "nat_eip" {
  count  = var.enable_internet_access ? 1 : 0
  domain = "vpc"

  tags = local.nat_eip_tags

  depends_on = [aws_internet_gateway.ec2_igw]
}

# Create Conditonal NAT Gateway 
resource "aws_nat_gateway" "ec2_nat" {
  count         = var.enable_internet_access ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = aws_subnet.public_subnet.id

  tags = local.nat_gateway_tags

  depends_on = [aws_internet_gateway.ec2_igw]
}

# Create NAT Gateway route
resource "aws_route" "ec2_route" {
  count                  = var.enable_internet_access ? 1 : 0
  route_table_id         = aws_route_table.ec2_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ec2_nat[0].id  
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
  cidr_ipv4         = var.private_subnet_cidr
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