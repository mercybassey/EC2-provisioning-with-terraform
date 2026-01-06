## Secure MySQL Deployment on AWS EC2 using Terraform, AWS SSM and Conditionl NAT Gateway

This project sets up an EC2 instance on AWS within a private subnet with no public IP address. An outbound-only conditional NAT gateway is configured to provide internet access, and secure remote administration of the instance is allowed using AWS Systems Manager Session Manager, eliminating the need for SSH and minimizing the exposure of inbound ports.

## The Problem

`*` How do I provision an EC2 instance running the latest official Canonical AMI using Terraform in a private subnet with no public IP address?

`*` How do I update the package index and install MySQL on this EC2 instance?

`*` How can I securely access the EC2 instance without using SSH?

`*` How do I connect to the MySQL server from MySQL Workbench (installed on my local machine) while the database is running on an EC2 instance in a private subnet?

## The Solution