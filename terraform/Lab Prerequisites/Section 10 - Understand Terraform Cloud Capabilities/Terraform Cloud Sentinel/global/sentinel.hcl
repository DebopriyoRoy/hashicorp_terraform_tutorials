# Common helper modules from HashiCorp’s examples
module "tfplan-functions" {
  source = "https://raw.githubusercontent.com/hashicorp/terraform-sentinel-policies/master/common-functions/tfplan-functions/tfplan-functions.sentinel"
}

module "tfconfig-functions" {
  source = "https://raw.githubusercontent.com/hashicorp/terraform-sentinel-policies/master/common-functions/tfconfig-functions/tfconfig-functions.sentinel"
}

# Map policy names to files by filename (no extension needed) and set enforcement
policy "enforce-mandatory-tags" {
  enforcement_level = "advisory"
}

policy "restrict-ec2-instance-type" {
  enforcement_level = "hard-mandatory"
}
