provider "cloudflare" {
  version = "<= 2.10.1"
}

resource "cloudflare_record" "domain" {
  zone_id = var.zone_id
  name    = var.domain
  value   = var.public_ip
  type    = "A"
}

