## Secure MySQL Deployment on AWS EC2 using Terraform, AWS SSM and Temporary NAT Gateway

This project demonstrates an infrastructure-as-code automation using Terraform to set up a production-grade MySQL database infrastructure on AWS. It features AWS EC2 instances, a Temporary NAT Gateway for cost-optimized outbound internet access, zero-trust access through the AWS SSM Session Manager, and VPC endpoints for private communication with AWS services.


## The Problem

**Security Challenge:**

* How do I provision an EC2 instance running the latest official Canonical AMI using Terraform in a private subnet with no public IP address?
* How can I securely access the EC2 instance without using SSH keys or exposing port 22?
* How do I provide temporary internet access for system updates and MySQL installation while maintaining security?

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
* Host the temporary NAT Gateway when internet access is needed in a public subnet (10.0.1.0/24)
**Security principle:** EC2 never gets directly exposed to internet.

**5. Temporary/Conditional NAT Gateway (Cost Optimization)**

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
  * Associate with the private subnet
  * No internet route when NAT Gateway is destroyed
