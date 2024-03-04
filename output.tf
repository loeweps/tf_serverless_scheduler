output "private_key" {
  value     = tls_private_key.demo_keys.private_key_pem
  sensitive = true
}

output "instance_id" {
  value = aws_instance.serverless_ec.id
}
