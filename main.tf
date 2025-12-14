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

data "aws_vpc" "default" {
    default = true
}

data "aws_subnets" "default_vpc_subnets" {
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.default.id]
    }
} 

data "aws_subnet" "default_vpc_subnet_details" {
  for_each = toset(data.aws_subnets.default_vpc_subnets.ids)
  id       = each.value
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

    sorted_subnet_ids = sort([
        for s in data.aws_subnet.default_vpc_subnet_details : s.id
    ])
}

# Create a Security Group
resource "aws_security_group" "allow_tls" {
  name = var.security_group
  vpc_id = data.aws_vpc.default.id
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
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = local.sorted_subnet_ids
  security_group_ids = [aws_security_group.allow_tls.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_instance_profile.name
  
  depends_on = [ 
    aws_iam_role_policy_attachment.ssm,
    aws_security_group.allow_tls
   ]

  root_block_device {
    volume_size = 20 
    volume_type = "gp3"
    encrypted = true
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

