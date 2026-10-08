module "ec2" {
  source              = "../../../../../modules/ec2"
  allowed_tls_domains = yamldecode(file("${path.root}/../firewall/config/egress.yml")).allowed_tls_domains
}
