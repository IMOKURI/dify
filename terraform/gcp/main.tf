terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPC Network
resource "google_compute_network" "dify_network" {
  name                    = "${var.prefix}-network"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "dify_subnet" {
  name          = "${var.prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.dify_network.id
}

# Firewall Rules - Allow HTTP/HTTPS from Load Balancer
resource "google_compute_firewall" "allow_lb" {
  name    = "${var.prefix}-allow-lb"
  network = google_compute_network.dify_network.name

  allow {
    protocol = "tcp"
    ports    = ["1080", "443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # Google Cloud Load Balancer IP ranges
  target_tags   = ["dify-instance"]
}

# Firewall Rules - Allow SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.prefix}-allow-ssh"
  network = google_compute_network.dify_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["dify-instance"]
}

# Firewall Rules - Allow Health Check
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.prefix}-allow-health-check"
  network = google_compute_network.dify_network.name

  allow {
    protocol = "tcp"
    ports    = ["1080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["dify-instance"]
}

# Static IP for Load Balancer
resource "google_compute_global_address" "dify_lb_ip" {
  name = "${var.prefix}-lb-ip"
}

# Compute Instance with Docker
resource "google_compute_instance" "dify_vm" {
  name         = "${var.prefix}-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["dify-instance"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.dify_network.name
    subnetwork = google_compute_subnetwork.dify_subnet.name

    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "${var.ssh_user}:${var.ssh_public_key}" : ""
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    docker_compose_version = var.docker_compose_version
  })

  service_account {
    email  = google_service_account.dify_sa.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Service Account for VM
resource "google_service_account" "dify_sa" {
  account_id   = "${var.prefix}-sa"
  display_name = "Dify Service Account"
}

# IAM binding for service account
resource "google_project_iam_member" "dify_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dify_sa.email}"
}

resource "google_project_iam_member" "dify_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.dify_sa.email}"
}

# Instance Group for Load Balancer
resource "google_compute_instance_group" "dify_ig" {
  name        = "${var.prefix}-ig"
  description = "Dify instance group"
  zone        = var.zone

  instances = [
    google_compute_instance.dify_vm.id,
  ]

  named_port {
    name = "http"
    port = "1080"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Health Check
resource "google_compute_health_check" "dify_health_check" {
  name                = "${var.prefix}-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 1080
    request_path = "/health"
  }
}

# Backend Service
resource "google_compute_backend_service" "dify_backend" {
  name                  = "${var.prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  health_checks         = [google_compute_health_check.dify_health_check.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_instance_group.dify_ig.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# URL Map
resource "google_compute_url_map" "dify_url_map" {
  name            = "${var.prefix}-url-map"
  default_service = google_compute_backend_service.dify_backend.id
}

# SSL Certificate (Google-managed)
resource "google_compute_managed_ssl_certificate" "dify_ssl_cert" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.prefix}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Self-signed SSL Certificate (for testing without domain)
resource "google_compute_ssl_certificate" "dify_self_signed" {
  count       = var.domain_name == "" ? 1 : 0
  name        = "${var.prefix}-self-signed-cert"
  private_key = var.ssl_private_key
  certificate = var.ssl_certificate

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "dify_https_proxy" {
  name    = "${var.prefix}-https-proxy"
  url_map = google_compute_url_map.dify_url_map.id
  ssl_certificates = var.domain_name != "" ? [
    google_compute_managed_ssl_certificate.dify_ssl_cert[0].id
    ] : [
    google_compute_ssl_certificate.dify_self_signed[0].id
  ]
}

# Global Forwarding Rule (HTTPS)
resource "google_compute_global_forwarding_rule" "dify_https_forwarding_rule" {
  name                  = "${var.prefix}-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.dify_https_proxy.id
  ip_address            = google_compute_global_address.dify_lb_ip.id
}
