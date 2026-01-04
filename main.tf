data "aws_ami" "ubuntu" {
    most_recent      = true
    owners           = ["099720109477"]

    filter {
        name = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"]
    } 

    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}



data "aws_iam_policy_document" "ec2_policy_document" {
    statement {
        effect = "Allow"

        principals {
            type = "Service"
            identifiers = ["ec2.amazonaws.com"]
        }

        actions = ["sts:AssumeRole"]
    }
}

locals {
    common_tags = {
        Project = "MySQL-Terraform"
        Environment = "Production"
        ManagedBy = "Terraform"
    }

    instance_tags = merge(local.common_tags, {
        Name = var.instance_name
    })
  
    security_group_tags = merge(local.common_tags, {
        Name = var.security_group
    })
    
    iam_role_tags = merge(local.common_tags, {
        Name = var.iam_role
    })

    vpc_tags = merge(local.common_tags, {
        Name = "mysql-production-vpc"
    })

    igw_tags = merge(local.common_tags, {
        Name = var.internet_gateway
    })
}

# Create a Custom VPC
resource "aws_vpc" "ec2_vpc" {
  cidr_block = var.vpc_cidr
  tags = local.vpc_tags
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create a Security Group
resource "aws_security_group" "allow_tls" {
  name = var.security_group
  vpc_id = aws_vpc.ec2_vpc.id
  tags = local.security_group_tags
}

# Create Egress Rule
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
    security_group_id = aws_security_group.allow_tls.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
    security_group_id = aws_security_group.allow_tls.id
    cidr_ipv6 = "::/0"
    ip_protocol = "-1"
}

# Create EC2 Instance
resource "aws_instance" "mysql_ec2_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type           = var.instance_type
  subnet_id               = local.sorted_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  depends_on = [
    aws_iam_role_policy_attachment.ssm
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
    name = var.iam_role

    assume_role_policy = data.aws_iam_policy_document.ec2_policy_document.json

    tags = local.iam_role_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role = aws_iam_role.ec2_ssm_role.name
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
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ec2_vpc.id

  tags = local.igw_tags
}
