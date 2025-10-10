/*output "hello-world" {
  description = "Print a Hello World text output"
  value       = "Hello World"
}*/
output "Terraform_instance_ip" {
  description = "Public IP Address of Web Server on EC2"
  value       = aws_instance.Terraform_instance.public_ip
  sensitive   = false
}
/*output "vpc_id" {
  description = "Output the ID for the primary VPC"
  value = aws_vpc.vpc.id
}*/

output "public_url" {
  description = "Public URL for our Web Server on EC2"
  value       = "https://${aws_instance.Terraform_instance.public_ip}:8080/index.html"
}

output "vpc_information" {
  description = "VPC Information about Environment"
  value       = "Your ${aws_vpc.vpc.tags.Environment} VPC has an ID of ${aws_vpc.vpc.id}"
}