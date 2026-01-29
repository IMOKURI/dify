# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "dify_postgres" {
  name             = "dify-postgres-${var.environment}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type
    disk_size         = 50
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.dify_vpc.id
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    database_flags {
      name  = "shared_buffers"
      value = "262144" # 128MB in 8kB pages
    }

    database_flags {
      name  = "work_mem"
      value = "4096" # 4MB in kB
    }

    database_flags {
      name  = "maintenance_work_mem"
      value = "65536" # 64MB in kB
    }

    database_flags {
      name  = "effective_cache_size"
      value = "286720" # ~280MB in 8kB pages (within allowed range)
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }

  deletion_protection = true

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Database
resource "google_sql_database" "dify_db" {
  name     = "dify"
  instance = google_sql_database_instance.dify_postgres.name
}

# Database user
resource "google_sql_user" "dify_user" {
  name     = "postgres"
  instance = google_sql_database_instance.dify_postgres.name
  password = var.db_password
}

# Private service connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "dify-private-ip-${var.environment}"
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
