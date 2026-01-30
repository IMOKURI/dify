terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# VPC Network
resource "google_compute_network" "dify_vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dify_subnet" {
  name          = "${var.prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.dify_vpc.id

  private_ip_google_access = true
}

# Cloud NAT for outbound internet access
resource "google_compute_router" "nat_router" {
  name    = "${var.prefix}-nat-router"
  region  = var.region
  network = google_compute_network.dify_vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.prefix}-allow-internal"
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

  source_ranges = [var.subnet_cidr]
}

resource "google_compute_firewall" "allow_lb_health_check" {
  name    = "${var.prefix}-allow-lb-health-check"
  network = google_compute_network.dify_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["${var.prefix}-web"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.prefix}-allow-ssh"
  network = google_compute_network.dify_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["${var.prefix}-compute"]
}

# Cloud SQL for PostgreSQL (Main Database)
resource "google_sql_database_instance" "postgres_main" {
  name             = "${var.prefix}-postgres-main"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type

    backup_configuration {
      enabled            = true
      start_time         = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.dify_vpc.id
    }

    database_flags {
      name  = "max_connections"
      value = var.postgres_max_connections
    }
  }

  deletion_protection = var.enable_deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "dify_db" {
  name     = var.db_database
  instance = google_sql_database_instance.postgres_main.name
}

resource "google_sql_user" "dify_user" {
  name     = var.db_username
  instance = google_sql_database_instance.postgres_main.name
  password = var.db_password
}

# Cloud SQL for PostgreSQL with pgvector (Vector Database)
resource "google_sql_database_instance" "postgres_vector" {
  name             = "${var.prefix}-postgres-vector"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.vector_db_tier
    availability_type = var.db_availability_type

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.dify_vpc.id
    }

    database_flags {
      name  = "cloudsql.enable_pgvector"
      value = "on"
    }
  }

  deletion_protection = var.enable_deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "vector_db" {
  name     = var.pgvector_database
  instance = google_sql_database_instance.postgres_vector.name
}

resource "google_sql_user" "vector_user" {
  name     = var.pgvector_user
  instance = google_sql_database_instance.postgres_vector.name
  password = var.pgvector_password
}

# Private VPC peering for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.prefix}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.dify_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.dify_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Memorystore for Redis
resource "google_redis_instance" "redis" {
  name               = "${var.prefix}-redis"
  tier               = var.redis_tier
  memory_size_gb     = var.redis_memory_size_gb
  region             = var.region
  redis_version      = "REDIS_6_X"
  auth_enabled       = true
  transit_encryption_mode = "DISABLED"

  authorized_network = google_compute_network.dify_vpc.id

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Cloud Storage bucket
resource "google_storage_bucket" "dify_storage" {
  name          = "${var.project_id}-${var.prefix}-storage"
  location      = var.region
  force_destroy = var.bucket_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
}

# Service account for Compute Engine instances
resource "google_service_account" "dify_compute" {
  account_id   = "${var.prefix}-compute"
  display_name = "Dify Compute Engine Service Account"
}

resource "google_project_iam_member" "dify_compute_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dify_compute.email}"
}

resource "google_project_iam_member" "dify_compute_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dify_compute.email}"
}

resource "google_project_iam_member" "dify_compute_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.dify_compute.email}"
}

# Service account key for Cloud Storage access
resource "google_service_account_key" "dify_storage_key" {
  service_account_id = google_service_account.dify_compute.name
}

# Instance template for Dify application
resource "google_compute_instance_template" "dify_app" {
  name_prefix  = "${var.prefix}-app-"
  machine_type = var.instance_type
  region       = var.region

  tags = ["${var.prefix}-web", "${var.prefix}-compute"]

  disk {
    source_image = var.instance_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.instance_disk_size
    disk_type    = "pd-balanced"
  }

  network_interface {
    network    = google_compute_network.dify_vpc.id
    subnetwork = google_compute_subnetwork.dify_subnet.id
  }

  service_account {
    email  = google_service_account.dify_compute.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/startup-script.sh", {
      db_host                                = google_sql_database_instance.postgres_main.private_ip_address
      db_port                                = "5432"
      db_username                            = var.db_username
      db_password                            = var.db_password
      db_database                            = var.db_database
      redis_host                             = google_redis_instance.redis.host
      redis_port                             = google_redis_instance.redis.port
      redis_password                         = google_redis_instance.redis.auth_string
      pgvector_host                          = google_sql_database_instance.postgres_vector.private_ip_address
      pgvector_port                          = "5432"
      pgvector_user                          = var.pgvector_user
      pgvector_password                      = var.pgvector_password
      pgvector_database                      = var.pgvector_database
      storage_bucket                         = google_storage_bucket.dify_storage.name
      service_account_json_base64            = google_service_account_key.dify_storage_key.private_key
      secret_key                             = var.secret_key
      init_password                          = var.init_password
      console_api_url                        = var.console_api_url
      console_web_url                        = var.console_web_url
      service_api_url                        = var.service_api_url
      app_api_url                            = var.app_api_url
      app_web_url                            = var.app_web_url
      files_url                              = var.files_url
      dify_version                           = var.dify_version
      log_level                              = var.log_level
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Health check for load balancer
resource "google_compute_health_check" "dify_http" {
  name                = "${var.prefix}-http-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# Managed instance group
resource "google_compute_region_instance_group_manager" "dify_mig" {
  name               = "${var.prefix}-mig"
  base_instance_name = "${var.prefix}-app"
  region             = var.region
  
  version {
    instance_template = google_compute_instance_template.dify_app.id
  }

  target_size = var.instance_count

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.dify_http.id
    initial_delay_sec = 300
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
    instance_redistribution_type = "PROACTIVE"
  }
}

# Autoscaler for managed instance group
resource "google_compute_region_autoscaler" "dify_autoscaler" {
  count = var.enable_autoscaling ? 1 : 0

  name   = "${var.prefix}-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.dify_mig.id

  autoscaling_policy {
    min_replicas    = var.autoscaling_min_replicas
    max_replicas    = var.autoscaling_max_replicas
    cooldown_period = 60

    cpu_utilization {
      target = var.autoscaling_cpu_target
    }
  }
}

# Reserve static external IP address for load balancer
resource "google_compute_global_address" "dify_lb" {
  name = "${var.prefix}-lb-ip"
}

# Load balancer backend service
resource "google_compute_backend_service" "dify_backend" {
  name                  = "${var.prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 3600
  enable_cdn            = false
  health_checks         = [google_compute_health_check.dify_http.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_region_instance_group_manager.dify_mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  session_affinity = "CLIENT_IP"
}

# URL map
resource "google_compute_url_map" "dify" {
  name            = "${var.prefix}-url-map"
  default_service = google_compute_backend_service.dify_backend.id
}

# HTTP proxy
resource "google_compute_target_http_proxy" "dify" {
  name    = "${var.prefix}-http-proxy"
  url_map = google_compute_url_map.dify.id
}

# Forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "dify_http" {
  name                  = "${var.prefix}-http-forwarding-rule"
  target                = google_compute_target_http_proxy.dify.id
  port_range            = "80"
  ip_address            = google_compute_global_address.dify_lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# HTTPS support (optional)
resource "google_compute_ssl_certificate" "dify" {
  count = var.enable_https ? 1 : 0

  name_prefix = "${var.prefix}-cert-"
  private_key = var.ssl_private_key
  certificate = var.ssl_certificate

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "dify" {
  count = var.enable_https ? 1 : 0

  name             = "${var.prefix}-https-proxy"
  url_map          = google_compute_url_map.dify.id
  ssl_certificates = [google_compute_ssl_certificate.dify[0].id]
}

resource "google_compute_global_forwarding_rule" "dify_https" {
  count = var.enable_https ? 1 : 0

  name                  = "${var.prefix}-https-forwarding-rule"
  target                = google_compute_target_https_proxy.dify[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.dify_lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
