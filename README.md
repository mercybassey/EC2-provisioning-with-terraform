## Secure MySQL Deployment on AWS EC2 using Terraform, AWS SSM and Conditional NAT Gateway

This project demonstrates an infrastructure-as-code automation using Terraform to set up a production-grade MySQL database infrastructure on AWS. It features AWS EC2 instances, a Conditional NAT Gateway for cost-optimized outbound internet access, zero-trust access through the AWS SSM Session Manager, and VPC endpoints for private communication with AWS services.

[Architectural Diagram](https://imgur.com/a/mBrDlL3.png)


## The Problem

**Security Challenge:**

* How do I provision an EC2 instance running the latest official Canonical AMI using Terraform in a private subnet with no public IP address?
* How can I securely access the EC2 instance without using SSH keys or exposing port 22?
* How do I provide conditional internet access for system updates and MySQL installation while maintaining security?

**Cost Challenge:**

* NAT Gateways cost $32/month even when idle - how can I minimize this expense?

**Operational Challenge:**

* How do I update the package index and install MySQL on an EC2 instance with no internet access?
* How do I connect to the MySQL server from MySQL Workbench (on my local machine) when the database runs in a completely private subnet?


## The Solution

### Infrastructure Architecture

**1. Dynamic AMI Selection**

* AWS regularly update the AMI IDs of operating systems when security patches or improvements become available. In this case, dynamically fetch the latest official Ubuntu 24.04 LTS AMI from Canonical instead of hardcoding it.
* Configure dynamic AMI selection using Terraform's data source decleration to  fetch the the most recent and secure image without any manual update or change to the Terraform code.
* **Filter criteria:** Architecture (x86_64), root device type (EBS), virtualization type (HVM)

**2. IAM Configuration for Systems Manager**

* Create an IAM assume-role policy that allows the EC2 service to assume a role.
* Attach the AWS managed policy `AmazonSSMManagedInstanceCore` for Systems Manager access.
* Create an IAM instance profile to bridge the role to the EC2 instance.
* **Result:** No SSH keys required, all access via IAM-authenticated Session Manager

**3. VPC Architecture**

* Provision a custom VPC (10.0.0.0/16) with DNS support and hostname resolution enabled since DNS services are required for VPC endpoints to function properly.
* **Security benefit:** Isolated network separate from default VPC.

**4. Subnet Segmentation**

* Host the MySQL EC2 instance in a private subnet (10.0.10.0/24) with no public IP assignment.
* Host the conditional NAT Gateway when internet access is needed in a public subnet (10.0.1.0/24)
**Security principle:** EC2 never gets directly exposed to internet.

**5. Conditional NAT Gateway (Cost Optimization)**

* Create only when `enable_internet_access = true`. (Terraform variable)
* Destroy when `enable_internet_access = false`.
* Reduce NAT Gateway costs from $32/month to $1-5/month (depending on the use).
* **Components:** Elastic IP, NAT Gateway, and conditional route in private route table.
* **Use case:** Enable temporarily for system updates and MySQL installation, then destroy.

**6. Route Table Design**

* Create a public route table to route all traffic (0.0.0.0/0) to Internet Gateway. 
  * Associate the the public route table with the public subnet to allow the NAT Gateway reach the internet.
* Create a private route table to route local VPC traffic (10.0.0.0/16) within the VPC.
  * Conditionally route internet traffic (0.0.0.0/0) to NAT Gateway when enabled.
  * Associate with the private subnet.
  * No internet route when NAT Gateway is destroyed.

**7. Security Group Configuration**

* **EC2 instance security group:**
  * **Inbound:** No rules (all inbound traffic blocked).
  * **Outbound:** All traffic allowed (for accessing VPC endpoints and internet via NAT).
* **VPC endpoint security group:**
  * **Inbound:** HTTPS (port 443) from private subnet CIDR only.
  * **Purpose:** Restrict endpoint access to EC2 instance only.


**8. EC2 Instance Provisioning**

* Launch instance in private subnet with no public IP assignment
* **Root volume:** 20 GB gp3, encrypted.
* **Instance type:** t3.micro (free tier eligible).
* **Subnet:** Private subnet ensures no direct internet exposure.
* **IAM instance profile:** Attached for Systems Manager access.

**9. IAM Role and Instance Profile**

* Create IAM role with EC2 service as a trusted principal.
* Attach `AmazonSSMManagedInstanceCore` policy to grant SSM permissions.
* Wrap role in an instance profile for EC2 attachment.
* **Result:** Instance can register with Systems Manager and accept management commands.

**10. VPC Endpoints for Private AWS Access**

* **SSM endpoint:** Systems Manager API calls.
* **SSM Messages endpoint:** Session Manager data streaming (terminal I/O).
* **EC2 Messages endpoint:** Instance registration and heartbeat.
* **Benefit:** All AWS communication stays within AWS private network (no internet required).
* **Cost:** ~$7.20/month per endpoint ($21.60 per month in total).

**11. VPC Endpoint Security Group**
* Dedicated security group for VPC endpoints.
* Allows HTTPS (port 443) traffic from private subnet CIDR only.
* **Security principle:** Restrict endpoint access to authorized resources only.

**12. Resource Dependencies**
* Use Terraform's `depends_on` meta-argument to ensure proper provisioning order:
  1. IAM role policy attachment must complete
  2. All three VPC endpoints must be available
  3. Then EC2 instance is created
* **Benefit:** Prevents provisioning failures due to [race conditions](https://support.hashicorp.com/hc/en-us/articles/18689474959379-Troubleshooting-Race-Conditions-in-Terraform).
* **Result:** SSM agent can register immediately upon instance boot.

**13. Parameterized Configuration**
* **Create Terraform variables for flexibility:**
  * `region`: AWS region (default: af*south*1)
  * `instance_type`: EC2 instance size (default: t3.micro)
  * `vpc_cidr`, `private_subnet_cidr`, `public_subnet_cidr`: Network ranges
  * `availability_zone`: AZ for resource placement (default: af*south*1b)
  * `enable_internet_access`: Boolean toggle for NAT Gateway (default: false)
* **Benefit:** Easy to adapt the infrastructure for different environments.

**14. Informative Outputs**
* **instance_id:** EC2 instance identifier (for SSM commands).
* **private_ip:** Instance's private IP address within the VPC.
* **ssm_session_command:** Ready-to-use command for terminal access.
* **internet_access_enabled:** Current state of NAT Gateway (true/false).
* **Benefit:** Immediate access to critical information after deployment.


## Security Architecture

### Multiple Security Layers:

**Layer 1 - Network Isolation:**
- Custom VPC with private subnet architecture.
- No public IP on EC2 instance.
- Instance cannot be directly accessed from internet.

**Layer 2 - Firewall (in form of Security Groups):**
- No inbound rules on EC2 security group.
- All inbound traffic blocked by default.
- Only VPC endpoints can reach instance via controlled paths.

**Layer 3 - Access Control (IAM):**
- IAM-based authentication for Systems Manager.
- No SSH keys to manage or compromise.
- MFA-capable authentication.
- Full audit trail in AWS CloudTrail.

**Layer 4 - Application (MySQL Configuration):**
- MySQL bound to localhost (127.0.0.1) only.
- Remote access via [SSM port forwarding tunnel](https://aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/).
- Encrypted connections end-to-end.

**Layer 5 - Conditional Internet:**
- Internet access only when explicitly enabled.
- NAT Gateway destroyed when not needed.
- Air-gapped by default.

## Cost Breakdown (Cape Town Region)

| Resource | Cost (Monthly) | Notes |
|----------|---------------|-------|
| EC2 t3.micro | $0 (Free Tier) | 750 hours/month free for first 12 months |
| EBS 20 GB gp3 | $0 (Free Tier) | 30 GB free for first 12 months |
| VPC Endpoints (3) | ~$28.68 | $9.56 per endpoint |
| NAT Gateway (conditional) | $0-3 | Only charged when enabled (~$0.057/hour) |
| Data Processing | ~$2-5 | VPC endpoint and NAT data processing |
| **Total** | **~$20-30/month** | With occasional NAT use |

**Cost Optimization:**
- Conditional NAT saves $42/month compared to permanent NAT Gateway
- Total savings: **60-95% reduction in NAT costs**

## Deployment Workflow

**1. Initial Deployment (No Internet):**

```bash
terraform init
terraform plan
terraform apply
```

**2. Enable Internet for MySQL Installation:**

```bash
terraform apply -var="enable_internet_access=true"
# Wait 5-7 minutes for NAT Gateway
```

**3. Install and Configure MySQL:**

```bash
aws ssm start-session --target ${aws_instance.ec2_instance.id}
sudo apt update
sudo apt install -y mysql-server
sudo mysql_secure_installation (optional)
sudo mysql

# Configure MySQL, create database and user


CREATE USER 'app_user'@'localhost' IDENTIFIED BY 'strongpassword';

exit
```

**4. Lock Down (Destroy NAT Gateway):**

```bash
terraform plan -var="enable_internet_access=false"
terraform apply -var="enable_internet_access=false"
```

**5. Connect MySQL Workbench:**

```bash
# Start port forwarding (keep it running)
aws ssm start-session --target  \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3306"],"localPortNumber":["3307"]}'

# Connect MySQL Workbench to localhost:3307
```

**6. MySQL Workbench Connection:**
* **Hostname:** `localhost` or `127.0.0.1`
* **Port:** `3307`
* **Username:** `app_user`
* **Password:** [your password]

**Traffic Flow:**
```bash
MySQL Workbench → localhost:3307 → SSM Client → VPC Endpoint →
SSM Agent on EC2 → localhost:3306 → MySQL Server
```

**Security Benefit:**
* MySQL never exposed beyond the instance
* All traffic encrypted through AWS private network
* No internet involved in database connections

## Key Technologies

* **Infrastructure as Code:** Terraform
* **Compute:** AWS EC2 (Ubuntu 24.04 LTS)
* **Networking:** AWS VPC, Subnets, NAT Gateway, Internet Gateway
* **Security:** VPC Endpoints, Security Groups, IAM Roles
* **Management:** AWS Systems Manager Session Manager
* **Database:** MySQL 8.x
* **Client Tool:** MySQL Workbench

Blog Post: https://medium.com/p/ac6336969862