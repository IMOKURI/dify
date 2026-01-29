# VPC Network
resource "google_compute_network" "dify_vpc" {
  name                    = "dify-vpc-${var.environment}"
  auto_create_subnetworks = false
  description             = "VPC network for Dify application"
}

# Subnet
resource "google_compute_subnetwork" "dify_subnet" {
  name          = "dify-subnet-${var.environment}"
  ip_cidr_range = var.network_cidr
  region        = var.region
  network       = google_compute_network.dify_vpc.id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.service_cidr
  }

  private_ip_google_access = true
}

# Cloud NAT for egress traffic
resource "google_compute_router" "dify_router" {
  name    = "dify-router-${var.environment}"
  region  = var.region
  network = google_compute_network.dify_vpc.id
}

resource "google_compute_router_nat" "dify_nat" {
  name                               = "dify-nat-${var.environment}"
  router                             = google_compute_router.dify_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "dify-allow-internal-${var.environment}"
  network = google_compute_network.dify_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.network_cidr, var.pod_cidr, var.service_cidr]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "dify-allow-ssh-${var.environment}"
  network = google_compute_network.dify_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP IP range
  target_tags   = ["dify-ssh"]
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "dify-allow-http-https-${var.environment}"
  network = google_compute_network.dify_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dify-web"]
}
