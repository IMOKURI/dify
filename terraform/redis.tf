# Memorystore for Redis
resource "google_redis_instance" "dify_redis" {
  name           = "dify-redis-${var.environment}"
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region

  authorized_network = google_compute_network.dify_vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  redis_version = "REDIS_6_X"
  display_name  = "Dify Redis Cache ${var.environment}"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
      }
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}
