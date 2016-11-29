variable "name" {}

variable "dns_name" {}

variable "region" {}

variable "private_subnets" {
  type = "list"
}

resource "google_compute_network" "network" {
  name = "${var.name}"
}

resource "google_compute_firewall" "ssh" {
  name = "${var.name}-ssh"
  network = "${google_compute_network.network.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

module "managed_dns" {
  source = "./managed_dns"

  name = "${var.name}"
  dns_name = "${var.dns_name}"
}

module "private_subnet" {
  source = "./private_subnet"

  name = "${var.name}-private"
  region = "${var.region}"
  network = "${google_compute_network.network.self_link}"
  cidrs = "${var.private_subnets}"
}
