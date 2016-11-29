variable "name" {}

variable "dns_name" {}

resource "google_dns_managed_zone" "platform" {
  name   = "${var.name}-dns-managed-zone"
  dns_name = "${var.dns_name}"
  description = "${var.name} managed DNS zone"
}

output "name_servers" {
  value = "[${google_dns_managed_zone.platform.name_servers}]"
}
