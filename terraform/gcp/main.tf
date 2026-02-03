terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

# =============================================================================
# Private Service Connection for Cloud SQL
# =============================================================================

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.prefix}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.dify_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.dify_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# =============================================================================
# Service Account Configuration
# =============================================================================

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

resource "google_project_iam_member" "dify_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dify_sa.email}"
}

# Service Account Key for GCS access (optional, only if needed outside GCE)
resource "google_service_account_key" "dify_sa_key" {
  count              = var.create_service_account_key ? 1 : 0
  service_account_id = google_service_account.dify_sa.name
}

# =============================================================================
# Random Passwords
# =============================================================================

# Random password for Cloud SQL (if not provided)
resource "random_password" "db_password" {
  count   = var.db_password == "" ? 1 : 0
  length  = 32
  special = true
}

# Random password for pgvector Cloud SQL (if not provided)
resource "random_password" "pgvector_db_password" {
  count   = var.enable_pgvector && var.pgvector_db_password == "" ? 1 : 0
  length  = 32
  special = true
}

# Random password for Redis AUTH (if enabled and not provided)
resource "random_password" "redis_auth_string" {
  count   = var.enable_redis && var.redis_auth_enabled ? 1 : 0
  length  = 32
  special = false # Redis AUTH string should not contain special characters
}

# =============================================================================
# Cloud SQL Configuration
# =============================================================================

# Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "dify_postgres" {
  name             = "${var.prefix}-postgres"
  database_version = var.cloudsql_database_version
  region           = var.region

  deletion_protection = true

  settings {
    tier              = var.cloudsql_tier
    disk_size         = var.cloudsql_disk_size
    disk_type         = "PD_SSD"
    availability_type = "ZONAL" # Use REGIONAL for high availability

    backup_configuration {
      enabled                        = var.cloudsql_backup_enabled
      start_time                     = var.cloudsql_backup_start_time
      point_in_time_recovery_enabled = var.cloudsql_backup_enabled
      transaction_log_retention_days = var.cloudsql_backup_enabled ? 7 : null

      dynamic "backup_retention_settings" {
        for_each = var.cloudsql_backup_enabled ? [1] : []
        content {
          retained_backups = 7
          retention_unit   = "COUNT"
        }
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.dify_network.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
}

# Database
resource "google_sql_database" "dify_db" {
  name     = var.db_name
  instance = google_sql_database_instance.dify_postgres.name
}

# Plugin Database
resource "google_sql_database" "dify_plugin_db" {
  name     = "${var.db_name}_plugin"
  instance = google_sql_database_instance.dify_postgres.name
}

# Database User
resource "google_sql_user" "dify_user" {
  name     = var.db_user
  instance = google_sql_database_instance.dify_postgres.name
  password = var.db_password != "" ? var.db_password : random_password.db_password[0].result
}

# =============================================================================
# pgvector Cloud SQL Instance (Optional)
# =============================================================================

# Cloud SQL PostgreSQL Instance with pgvector extension
resource "google_sql_database_instance" "dify_pgvector" {
  count            = var.enable_pgvector ? 1 : 0
  name             = "${var.prefix}-pgvector"
  database_version = var.pgvector_database_version
  region           = var.region

  deletion_protection = var.pgvector_deletion_protection

  settings {
    tier              = var.pgvector_tier
    disk_size         = var.pgvector_disk_size
    disk_type         = "PD_SSD"
    availability_type = var.pgvector_availability_type

    backup_configuration {
      enabled                        = var.pgvector_backup_enabled
      start_time                     = var.pgvector_backup_start_time
      point_in_time_recovery_enabled = var.pgvector_backup_enabled
      transaction_log_retention_days = var.pgvector_backup_enabled ? 7 : null

      dynamic "backup_retention_settings" {
        for_each = var.pgvector_backup_enabled ? [1] : []
        content {
          retained_backups = var.pgvector_backup_retention_count
          retention_unit   = "COUNT"
        }
      }
    }

    ip_configuration {
      ipv4_enabled    = var.pgvector_enable_public_ip
      private_network = google_compute_network.dify_network.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"

      dynamic "authorized_networks" {
        for_each = var.pgvector_authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
    }

    # Database flags for pgvector optimization
    # Note: Cloud SQL auto-manages memory settings based on instance tier
    database_flags {
      name  = "max_connections"
      value = var.pgvector_max_connections
    }

    # pgvector extension is automatically available in Cloud SQL PostgreSQL 11+
    # No need to set shared_preload_libraries

    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = var.pgvector_query_insights_enabled
      query_plans_per_minute  = var.pgvector_query_insights_enabled ? 5 : null
      query_string_length     = var.pgvector_query_insights_enabled ? 1024 : null
      record_application_tags = var.pgvector_query_insights_enabled ? true : null
    }

    maintenance_window {
      day          = var.pgvector_maintenance_window_day
      hour         = var.pgvector_maintenance_window_hour
      update_track = "stable"
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
}

# Database for vector storage
resource "google_sql_database" "pgvector_db" {
  count    = var.enable_pgvector ? 1 : 0
  name     = var.pgvector_db_name
  instance = google_sql_database_instance.dify_pgvector[0].name
}

# Database User for pgvector
resource "google_sql_user" "pgvector_user" {
  count    = var.enable_pgvector ? 1 : 0
  name     = var.pgvector_db_user
  instance = google_sql_database_instance.dify_pgvector[0].name
  password = var.pgvector_db_password != "" ? var.pgvector_db_password : random_password.pgvector_db_password[0].result
}

# Optional: Create a read replica for high availability and read scaling
resource "google_sql_database_instance" "dify_pgvector_replica" {
  count                = var.enable_pgvector && var.pgvector_enable_read_replica ? 1 : 0
  name                 = "${var.prefix}-pgvector-replica"
  master_instance_name = google_sql_database_instance.dify_pgvector[0].name
  region               = var.pgvector_replica_region != "" ? var.pgvector_replica_region : var.region
  database_version     = var.pgvector_database_version

  deletion_protection = var.pgvector_deletion_protection

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = var.pgvector_replica_tier != "" ? var.pgvector_replica_tier : var.pgvector_tier
    disk_size         = var.pgvector_disk_size
    disk_type         = "PD_SSD"
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = var.pgvector_enable_public_ip
      private_network = google_compute_network.dify_network.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }

    # Inherit database flags from master
    database_flags {
      name  = "max_connections"
      value = var.pgvector_max_connections
    }

    insights_config {
      query_insights_enabled = var.pgvector_query_insights_enabled
    }
  }
}

# =============================================================================
# Google Cloud Storage Configuration
# =============================================================================

# GCS Bucket for file storage
resource "google_storage_bucket" "dify_storage" {
  name          = var.gcs_bucket_name != "" ? var.gcs_bucket_name : "${var.project_id}-${var.prefix}-storage"
  location      = var.gcs_location
  force_destroy = var.gcs_force_destroy
  storage_class = var.gcs_storage_class

  uniform_bucket_level_access = true

  versioning {
    enabled = var.gcs_versioning_enabled
  }

  dynamic "lifecycle_rule" {
    for_each = var.gcs_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lookup(lifecycle_rule.value.action, "storage_class", null)
      }

      condition {
        age                   = lookup(lifecycle_rule.value.condition, "age", null)
        created_before        = lookup(lifecycle_rule.value.condition, "created_before", null)
        with_state            = lookup(lifecycle_rule.value.condition, "with_state", null)
        matches_storage_class = lookup(lifecycle_rule.value.condition, "matches_storage_class", null)
        num_newer_versions    = lookup(lifecycle_rule.value.condition, "num_newer_versions", null)
      }
    }
  }

  dynamic "cors" {
    for_each = var.gcs_cors_enabled ? [1] : []
    content {
      origin          = var.gcs_cors_origins
      method          = var.gcs_cors_methods
      response_header = var.gcs_cors_response_headers
      max_age_seconds = var.gcs_cors_max_age_seconds
    }
  }

  labels = merge(
    {
      environment = var.prefix
      managed_by  = "terraform"
    },
    var.gcs_labels
  )
}

# =============================================================================
# Redis Memorystore Configuration
# =============================================================================

# Reserved IP range for Redis (if specified)
resource "google_compute_global_address" "redis_ip_range" {
  count         = var.enable_redis && var.redis_reserved_ip_range != "" ? 1 : 0
  name          = "${var.prefix}-redis-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 29 # Redis requires /29
  network       = google_compute_network.dify_network.id
  address       = split("/", var.redis_reserved_ip_range)[0]
}

# Redis Memorystore Instance
resource "google_redis_instance" "dify_redis" {
  count                   = var.enable_redis ? 1 : 0
  name                    = "${var.prefix}-redis"
  tier                    = var.redis_tier
  memory_size_gb          = var.redis_memory_size_gb
  region                  = var.region
  redis_version           = var.redis_version
  replica_count           = var.redis_tier == "STANDARD_HA" ? var.redis_replica_count : null
  auth_enabled            = var.redis_auth_enabled
  transit_encryption_mode = var.redis_transit_encryption_mode
  connect_mode            = var.redis_connect_mode
  authorized_network      = google_compute_network.dify_network.id
  reserved_ip_range       = var.redis_reserved_ip_range != "" ? var.redis_reserved_ip_range : null

  # Persistence configuration (only for STANDARD_HA tier)
  dynamic "persistence_config" {
    for_each = var.redis_tier == "STANDARD_HA" && var.redis_persistence_mode == "RDB" ? [1] : []
    content {
      persistence_mode        = "RDB"
      rdb_snapshot_period     = var.redis_rdb_snapshot_period
      rdb_snapshot_start_time = var.redis_rdb_snapshot_start_time != "" ? var.redis_rdb_snapshot_start_time : null
    }
  }

  # Maintenance policy
  maintenance_policy {
    weekly_maintenance_window {
      day = var.redis_maintenance_window_day
      start_time {
        hours   = var.redis_maintenance_window_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # Redis configuration parameters
  redis_configs = {
    # Timeout for idle connections (in seconds)
    "timeout" = "300"

    # Maximum number of connected clients
    "maxmemory-policy" = "allkeys-lru"

    # Notify keyspace events
    "notify-keyspace-events" = ""
  }

  labels = merge(
    {
      environment = var.prefix
      managed_by  = "terraform"
    },
    var.redis_labels
  )

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [
    google_compute_network.dify_network,
    google_service_networking_connection.private_vpc_connection
  ]
}

# =============================================================================
# Compute Instance
# =============================================================================

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
    ssh-keys = local.ssh_public_key_content != "" ? "${var.ssh_user}:${local.ssh_public_key_content}" : ""
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

  # Deploy .env.example file to VM with Cloud SQL configuration
  provisioner "file" {
    content = templatefile("${path.root}/.env.example", {
      db_host                                    = google_sql_database_instance.dify_postgres.private_ip_address
      database_user                              = var.db_user
      database_password                          = var.db_password != "" ? var.db_password : random_password.db_password[0].result
      database_name                              = var.db_name
      pgvector_private_ip                        = var.enable_pgvector ? google_sql_database_instance.dify_pgvector[0].private_ip_address : "pgvector"
      pgvector_database_user                     = var.enable_pgvector ? var.pgvector_db_user : "postgres"
      pgvector_database_password                 = var.enable_pgvector ? (var.pgvector_db_password != "" ? var.pgvector_db_password : random_password.pgvector_db_password[0].result) : "difyai123456"
      pgvector_database_name                     = var.enable_pgvector ? var.pgvector_db_name : "dify"
      gcs_bucket_name                            = google_storage_bucket.dify_storage.name
      google_storage_service_account_json_base64 = var.create_service_account_key ? base64encode(google_service_account_key.dify_sa_key[0].private_key) : ""
      redis_host                                 = var.enable_redis ? google_redis_instance.dify_redis[0].host : "redis"
      redis_auth_string                          = var.enable_redis && var.redis_auth_enabled ? google_redis_instance.dify_redis[0].auth_string : ""
    })
    destination = "/tmp/.env"

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = local.ssh_private_key_content != "" ? local.ssh_private_key_content : null
      host        = self.network_interface[0].access_config[0].nat_ip
    }
  }

  # Download and extract Dify source code
  provisioner "remote-exec" {
    inline = [
      "curl -L https://github.com/langgenius/dify/archive/refs/tags/${var.dify_version}.tar.gz -o /tmp/dify-${var.dify_version}.tar.gz",
      "sudo tar -xzf /tmp/dify-${var.dify_version}.tar.gz -C /opt/",
      "sudo mv /tmp/.env /opt/dify-${var.dify_version}/docker/.env",
      "sudo chown -R ubuntu:ubuntu /opt/dify-${var.dify_version}"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = local.ssh_private_key_content != "" ? local.ssh_private_key_content : null
      host        = self.network_interface[0].access_config[0].nat_ip
    }
  }
}

# =============================================================================
# Load Balancer Configuration
# =============================================================================

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
