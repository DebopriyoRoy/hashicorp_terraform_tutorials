output "public_ip" {
  description = "IP Address of server built with Server Module"
  value       = aws_instance.Tf_server_web.public_ip
}

output "public_dns" {
  description = "DNS Address of server built with Server Module"
  value       = aws_instance.Tf_server_web.public_dns
}
output "size" {
  description = "Size of server built with Server Module"
  value       = aws_instance.Tf_server_web.instance_type
}