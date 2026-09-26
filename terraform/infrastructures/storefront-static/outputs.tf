output "certificate_validation_records" {
  description = "Create these in Cloudflare as DNS only (grey cloud) before the full apply"
  value = [
    for option in aws_acm_certificate.site.domain_validation_options : {
      type  = option.resource_record_type
      name  = option.resource_record_name
      value = option.resource_record_value
    }
  ]
}

output "site_cname" {
  description = "Point the storefront's host at this, as DNS only (grey cloud)"
  value = {
    name   = var.domain_name
    target = module.site.domain_name
  }
}

output "site_url" {
  value = "https://${var.domain_name}"
}

# The three values the storefront's workflow needs, as variables of its
# production environment.
output "github_environment_variables" {
  value = {
    AWS_DEPLOY_ROLE_ARN = module.deploy_role.role_arn
    SITE_BUCKET         = module.site.bucket_name
    DISTRIBUTION_ID     = module.site.distribution_id
  }
}

output "content_security_policy" {
  value = local.content_security_policy
}
