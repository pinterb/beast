variable "name" {}

variable "zone" {}

variable "network" {}

variable "subnet" {}

variable "node_count" {}

variable "master_user" {}

variable "master_password" {}

variable "instance_type" {}

variable "oauth_scopes" {
  type = "list"
  default = [
    "https://www.googleapis.com/auth/projecthosting",
    "https://www.googleapis.com/auth/devstorage.full_control",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/datastore",
    "https://www.googleapis.com/auth/sqlservice.admin",
    "https://www.googleapis.com/auth/bigquery",
    "https://www.googleapis.com/auth/analytics",
    "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
    "https://www.googleapis.com/auth/pubsub"
  ]
}

resource "google_container_cluser" "k8s_cluster" {
  name         = "${var.name}"
  network      = "${var.network}"
  subnetwork   = "${var.subnet}"
  zone         = "${var.zone}"

  initial_node_count = "${var.node_count}"

  master_auth {
    username = "${var.master_user}"
    password = "${var.master_password}"
  }

  node_config {
    machine_type = "${var.instance_type}"
    oauth_scopes = "${var.oauth_scopes}"
  }
}
