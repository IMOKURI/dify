output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_address.dify_lb.address
}

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.dify_vpc.name
}

output "postgres_main_connection_name" {
  description = "Connection name for the main PostgreSQL instance"
  value       = google_sql_database_instance.postgres_main.connection_name
}

output "postgres_main_private_ip" {
  description = "Private IP address of the main PostgreSQL instance"
  value       = google_sql_database_instance.postgres_main.private_ip_address
}

output "postgres_vector_connection_name" {
  description = "Connection name for the pgvector PostgreSQL instance"
  value       = google_sql_database_instance.postgres_vector.connection_name
}

output "postgres_vector_private_ip" {
  description = "Private IP address of the pgvector PostgreSQL instance"
  value       = google_sql_database_instance.postgres_vector.private_ip_address
}

output "redis_host" {
  description = "Redis instance host"
  value       = google_redis_instance.redis.host
}

output "redis_port" {
  description = "Redis instance port"
  value       = google_redis_instance.redis.port
}

output "redis_auth_string" {
  description = "Redis authentication string"
  value       = google_redis_instance.redis.auth_string
  sensitive   = true
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket"
  value       = google_storage_bucket.dify_storage.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.dify_storage.url
}

output "instance_group_manager_name" {
  description = "Name of the managed instance group"
  value       = google_compute_region_instance_group_manager.dify_mig.name
}

output "service_account_email" {
  description = "Email of the service account used by Compute Engine instances"
  value       = google_service_account.dify_compute.email
}

output "access_url_http" {
  description = "HTTP URL to access the Dify application"
  value       = "http://${google_compute_global_address.dify_lb.address}"
}

output "access_url_https" {
  description = "HTTPS URL to access the Dify application (if HTTPS is enabled)"
  value       = var.enable_https ? "https://${google_compute_global_address.dify_lb.address}" : "HTTPS not enabled"
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "primary_zone" {
  description = "Primary zone for compute instances"
  value       = "${var.region}-a"
}
