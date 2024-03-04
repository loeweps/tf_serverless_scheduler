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
  key_name = aws_key_pair.generated_key.key_name
  
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
resource "aws_iam_policy" "stop_policy" {
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

#Create role for Lambda to assume
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Create a role for Lambda function to start EC2 instances
resource "aws_iam_role" "lambda_start_role" {
  name               = "lambda_start_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Attach the start policy to the role
resource "aws_iam_policy_attachment" "start_lambda_policy_attachment" {
  name       = "lambda_start_policy_attachment"
  roles      = [aws_iam_role.lambda_start_role.name]
  policy_arn = aws_iam_policy.start_policy.arn
}

# Create a role for Lambda function to stop EC2 instances
resource "aws_iam_role" "lambda_stop_role" {
  name               = "lambda_stop_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Attach the stop policy to the role
resource "aws_iam_policy_attachment" "stop_lambda_policy_attachment" {
  name       = "lambda_stop_policy_attachment"
  roles      = [aws_iam_role.lambda_stop_role.name]
  policy_arn = aws_iam_policy.stop_policy.arn
}

#Lambda start package
data "archive_file" "python_lambda_start_package" {  
  type = "zip"  
  source_file = "./code/start-ec2-instance.py" 
  output_path = "lambda_start_function.zip"
}

#Lambda stop package
data "archive_file" "python_lambda_stop_package" {  
  type = "zip"  
  source_file = "./code/stop-ec2-instance.py" 
  output_path = "lambda_stop_function.zip"
}

#Lambda start function
resource "aws_lambda_function" "lambda_start" {
  function_name = "lambda_start_function"
  role          = aws_iam_role.lambda_start_role.arn
  handler       = "start-ec2-instance.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_start_function.zip"
  timeout       = 15

  environment {
    variables = {
      INSTANCE_ID = aws_instance.serverless_ec.id
    }
  }
}

#Lambda stop function
resource "aws_lambda_function" "lambda_stop" {
  function_name = "lambda_stop_function"
  role          = aws_iam_role.lambda_stop_role.arn
  handler       = "stop-ec2-instance.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_stop_function.zip"
  timeout       = 15

  environment {
    variables = {
      INSTANCE_ID = aws_instance.serverless_ec.id
    }
  }
}

#Cloudwatch rule to start the ec2 instance every 15 minutes
resource "aws_cloudwatch_event_rule" "start_schedule" {
  name        = "start-ec2-rule"
  description = "Rule to start the instance"
  state       = "ENABLED"
  schedule_expression = "cron(0/15/30/45 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "start_target" {
  rule      = aws_cloudwatch_event_rule.start_schedule.name
  arn       = aws_lambda_function.lambda_start.arn
}

#Cloudwatch rule to stop the ec2 instance 5 minutes after start
resource "aws_cloudwatch_event_rule" "stop_schedule" {
  name        = "stop-ec2-rule"
  description = "Rule to stop the instance 5 minutes after start"
  state       = "ENABLED"
  schedule_expression = "cron(5/20/35/50 * * * ? *)"

}

resource "aws_cloudwatch_event_target" "stop_target" {
  rule      = aws_cloudwatch_event_rule.stop_schedule.name
  arn       = aws_lambda_function.lambda_stop.arn
}

