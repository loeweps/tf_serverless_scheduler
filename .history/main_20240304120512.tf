terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

#Generate key pairs for access to EC
variable "key_name" {}

resource "tls_private_key" "demo_keys" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.demo_keys.public_key_openssh
}

# Create an AMI instance that will start a machine whose root device is backed by
# an EBS volume
resource "aws_instance" "serverless_ec" {
  ami = "ami-0440d3b780d96b29d"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = var.key_name
  
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = 8
    volume_type = "gp3"
  }
  
  tags = {
    Name = "serverless-demo-instance"
  }
}

#Security group to allow ssh
resource "aws_security_group" "serverless_ssh" {
  name        = "serverless_sg"
  description = "Allow SSH access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#Create a policy to allow starting instances
resource "aws_iam_policy" "start_policy" {
  name        = "start_ec2_instance"
  description = "My serverless start policy"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

#Create a policy to allow stopping instances
resource "aws_iam_policy" "stopping_policy" {
  name        = "stop_ec2_instance"
  description = "My serverless stop policy"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


data "archive_file" "python_lambda_start_package" {  
  type = "zip"  
  source_file = "./code/start_function.py" 
  output_path = "lambda_start_function.zip"
}

data "archive_file" "python_lambda_stop_package" {  
  type = "zip"  
  source_file = "./code/stop_function.py" 
  output_path = "lambda_stop_function.zip"
}

resource "aws_lambda_function" "lambda_start" {
  function_name = "Lambda_start_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_start_function.zip"

  environment {
    variables = {
      INSTANCE_ID = aws_instance.serverless_ec.id
    }
  }
}

resource "aws_lambda_function" "lambda_stop" {
  function_name = "Lambda_stop_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_stop_function.zip"

  environment {
    variables = {
      INSTANCE_ID = aws_instance.serverless_ec.id
    }
  }
}



