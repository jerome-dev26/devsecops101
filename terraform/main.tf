# main.tf

# 1. VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.vpc_name
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# 3. Public Subnets (we'll use two for high availability)
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${count.index + 1}"
  }
}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# 4. Route Table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# 5. Associate subnets with the route table
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 6. Security Group
resource "aws_security_group" "securedock_sg" {
  name        = "securedock-sg"
  description = "Allow HTTP/HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "securedock-sg"
  }
}

# 7. IAM Role for EC2 (so it can access AWS services like Secrets Manager)
resource "aws_iam_role" "ec2_role" {
  name = "securedock-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"   # Allows SSM (optional)
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "securedock-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# 8. EC2 Instance (Ubuntu 22.04)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "securedock" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public[0].id   # Place in first public subnet
  vpc_security_group_ids = [aws_security_group.securedock_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  /*user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt install -y docker.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    # Install git for cloning repo
    apt install -y git
    # (Later we'll have CI/CD deploy the app)
  EOF
  */
  
  user_data = <<-EOF
    #!/bin/bash
    # Prevent interactive prompts during installation
    export DEBIAN_FRONTEND=noninteractive

    # Update system packages
    apt-get update -y
              
    # Install Docker and dependencies
    apt-get install -y docker.io docker-compose git
              
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
              
    # Add the default ubuntu user to the docker group
    usermod -aG docker ubuntu

    # Install git for cloning repo
    apt install -y git
    # (Later we'll have CI/CD deploy the app)
  EOF




  tags = {
    Name = "securedock-platform"
  }
}

# 9. Outputs (we'll see these after apply)
output "sec_ec2_public_ip" {
  value = aws_instance.securedock.public_ip
}

output "sec_ec2_public_dns" {
  value = aws_instance.securedock.public_dns
}

output "sec_vpc_id" {
  value = aws_vpc.main.id
}
