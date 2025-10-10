/*# Configure the AWS Provider
provider "aws" {
  region = "ca-central-1"
}*/

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
locals {
  # List of AZ names in the current region, e.g., ["ca-central-1a","ca-central-1b","ca-central-1d"]
  az_names = data.aws_availability_zones.available.names
}

locals {
  team        = "api_mgmt_dev"
  application = "corp_api"
  server_name = "ec2-${var.environment}-api-${var.variables_sub_az}"
}

#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = var.vpc_name
    Environment = "demo_environment"
    Terraform   = "true"
    Region      = data.aws_region.current.name

  }
}

#Deploy the private subnets
resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = local.az_names[(each.value - 1) % length(local.az_names)]
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone       = local.az_names[(each.value - 1) % length(local.az_names)]
  map_public_ip_on_launch = true

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_public_rtb"
    Terraform = "true"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id     = aws_internet_gateway.internet_gateway.id
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_private_rtb"
    Terraform = "true"
  }
}

#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}

resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}

#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "demo_igw"
  }
}

#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "demo_igw_eip"
  }
}

#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "demo_nat_gateway"
  }
}

# Terraform Data Block - Lookup Ubuntu 22.04
data "aws_ami" "ubuntu_20_04" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "Terraform_instance" {
  ami                         = data.aws_ami.ubuntu_20_04.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups             = [aws_security_group.my-security-group.id, aws_security_group.vpc-ping.id, aws_security_group.ingress-ssh.id, aws_security_group.vpc-web.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name
  connection {
    user        = "ubuntu"
    private_key = tls_private_key.generated.private_key_pem
    host        = self.public_ip
  }

  provisioner "local-exec" {
    command = "powershell -Command \"icacls ${local_file.private_key_pem.filename} /inheritance:r; icacls ${local_file.private_key_pem.filename} /grant:r $($env:USERNAME):R\""
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /tmp",
      "sudo git clone https://github.com/hashicorp/demo-terraform-101 /tmp",
      "sudo sh /tmp/assets/setup-web.sh",
    ]
  }
  tags = {
    Name  = local.server_name
    Owner = local.team
    App   = local.application
  }
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "MyTerraformInstanceKey.pem"
}
resource "aws_key_pair" "generated" {
  key_name   = "MyTerraformInstanceKey"
  public_key = tls_private_key.generated.public_key_openssh

  lifecycle {
    ignore_changes = [key_name]
  }
}

/*resource "aws_instance" "aws_linux" {
  ami           = "ami-029c5475368ac7adc"
  instance_type = "t3.micro"
  tags = {
    Name        = "Imported_EC2Inst"
    Provisioned = "Terraform  Import"
  }
}*/

module "server" {
  source    = "./modules/server"
  ami       = data.aws_ami.ubuntu_20_04.id
  subnet_id = aws_subnet.public_subnets["public_subnet_3"].id
  security_groups = [
    aws_security_group.vpc-ping.id,
    aws_security_group.ingress-ssh.id,
    aws_security_group.vpc-web.id
  ]
}

output "public_ip" {
  value = module.server.public_ip
}

output "public_dns" {
  value = module.server.public_dns
}

module "server_subnet_1" {
  source      = "./modules/web_server"
  ami         = data.aws_ami.ubuntu_20_04.id
  key_name    = aws_key_pair.generated.key_name
  user        = "ubuntu"
  private_key = tls_private_key.generated.private_key_pem
  subnet_id   = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups = [aws_security_group.vpc-ping.id,
    aws_security_group.ingress-ssh.id,
  aws_security_group.vpc-web.id]
}

output "public_ip_server_subnet_1" {
  value = module.server_subnet_1.public_ip
}

output "public_dns_server_subnet_1" {
  value = module.server_subnet_1.public_dns
}

###Explore the Public Module Registry and install a module
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.0.1"
 
  # Autoscaling group
  name = "myasg_local"
 
  vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id, 
  aws_subnet.private_subnets["private_subnet_2"].id, 
  aws_subnet.private_subnets["private_subnet_3"].id]
  min_size            = 0
  max_size            = 1
  desired_capacity    = 1
 
  # Launch template
  image_id      = data.aws_ami.ubuntu_20_04.id
  instance_type = "t3.micro"
  instance_name = "asg-instance_local"
 
  tags = {
    Name = "Web EC2 Server local"
  }
 
}

###Source a module from GitHub
module "autoscaling_github" {
  source = "github.com/terraform-aws-modules/terraform-aws-autoscaling?ref=v4.9.0"
  #version = "8.0.1"
 
  # Autoscaling group
  name = "myasg_github"
 
  vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id, 
  aws_subnet.private_subnets["private_subnet_2"].id, 
  aws_subnet.private_subnets["private_subnet_3"].id]
  min_size            = 0
  max_size            = 1
  desired_capacity    = 1
 
   # Launch template
  use_lt    = true
  create_lt = true

  image_id      = data.aws_ami.ubuntu_20_04.id
  instance_type = "t3.micro"
  instance_name = "asg-instance_github"
 

  tags_as_map = {
    Name = "Web EC2 Server github"
  }

}

## USE CASE FOR LOCAL VARIABLES##

/*resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name  = local.server_name
    Owner = local.team
    App   = local.application
  }
}*/

/*resource "aws_s3_bucket" "my-new-S3-bucket" {
  bucket = "terraform-handson-lab-${random_id.randomness.hex}"

  tags = {
    Name    = "Terraform-learning-bucket"
    Purpose = "Intro to Resource Blocks Lab"
  }
}

resource "aws_s3_bucket_ownership_controls" "my_new_bucket_ownership" {
  bucket = aws_s3_bucket.my-new-S3-bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Set ACL (must be separate)
resource "aws_s3_bucket_acl" "my_new_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.my_new_bucket_ownership]
  bucket = aws_s3_bucket.my-new-S3-bucket.id
  acl        = "private"
}*/

# creating Security Group

resource "aws_security_group" "my-security-group" {
  name        = "web_server_inbound"
  description = "Allow inbound traffic on tcp/443"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow 443 from the Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "web_server_inbound"
    Purpose = "Intro to Resource Blocks Lab"
  }
}
# Security Groups

resource "aws_security_group" "ingress-ssh" {
  name   = "allow-all-ssh"
  vpc_id = aws_vpc.vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Create Security Group - Web Traffic
resource "aws_security_group" "vpc-web" {
  name        = "vpc-web-${terraform.workspace}"
  vpc_id      = aws_vpc.vpc.id
  description = "Web Traffic"
  ingress {
    description = "Allow Port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpc-ping" {
  name        = "vpc-ping"
  vpc_id      = aws_vpc.vpc.id
  description = "ICMP for Ping Access"
  ingress {
    description = "Allow ICMP Traffic"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
/*
resource "random_id" "randomness" {
  byte_length = 16
}*/

resource "aws_subnet" "variables-subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.variables_sub_cidr
  availability_zone       = var.variables_sub_az
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = {
    Name      = "sub-variables-${var.variables_sub_az}"
    Terraform = "true"
  }
}

/*
#### IN THE TERMINAL, WHEN PROMPTED, TYPE THE FOLLOWING VALUE:

for var.variables_sub_auto_ip, type in "true" and press enter
for var.variables_sub_az, type in "ca-central-1a" and press enter
for var.variables_sub_cidr, type in "10.0.250.0/24" and press enter
*/