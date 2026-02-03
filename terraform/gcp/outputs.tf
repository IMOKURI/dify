output "load_balancer_ip" {
  description = "Load Balancer IP address"
  value       = google_compute_global_address.dify_lb_ip.address
}

output "vm_instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.dify_vm.name
}

output "vm_instance_ip" {
  description = "VM instance external IP"
  value       = google_compute_instance.dify_vm.network_interface[0].access_config[0].nat_ip
}

output "vm_zone" {
  description = "VM instance zone"
  value       = google_compute_instance.dify_vm.zone
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "gcloud compute ssh ${google_compute_instance.dify_vm.name} --zone ${var.zone} --project ${var.project_id}"
}

output "https_url" {
  description = "HTTPS URL to access the application"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${google_compute_global_address.dify_lb_ip.address}"
}

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.dify_postgres.name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.dify_postgres.connection_name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.dify_postgres.private_ip_address
}

output "cloudsql_public_ip" {
  description = "Cloud SQL public IP address"
  value       = google_sql_database_instance.dify_postgres.public_ip_address
}

output "database_name" {
  description = "Database name"
  value       = google_sql_database.dify_db.name
}

output "database_user" {
  description = "Database user"
  value       = google_sql_user.dify_user.name
  sensitive   = true
}

output "database_password" {
  description = "Database password"
  value       = var.db_password != "" ? var.db_password : random_password.db_password[0].result
  sensitive   = true
}

output "database_url" {
  description = "PostgreSQL connection URL (use private IP for VM)"
  value       = "postgresql://${google_sql_user.dify_user.name}:${var.db_password != "" ? var.db_password : random_password.db_password[0].result}@${google_sql_database_instance.dify_postgres.private_ip_address}:5432/${google_sql_database.dify_db.name}"
  sensitive   = true
}

# =============================================================================
# pgvector Outputs
# =============================================================================

output "pgvector_instance_name" {
  description = "Name of the pgvector Cloud SQL instance"
  value       = google_sql_database_instance.dify_pgvector.name
}

output "pgvector_connection_name" {
  description = "Connection name for the pgvector Cloud SQL instance"
  value       = google_sql_database_instance.dify_pgvector.connection_name
}

output "pgvector_private_ip" {
  description = "Private IP address of the pgvector Cloud SQL instance"
  value       = google_sql_database_instance.dify_pgvector.private_ip_address
}

output "pgvector_public_ip" {
  description = "Public IP address of the pgvector Cloud SQL instance (if enabled)"
  value       = var.pgvector_enable_public_ip ? google_sql_database_instance.dify_pgvector.public_ip_address : null
}

output "pgvector_database_name" {
  description = "Database name for pgvector"
  value       = google_sql_database.pgvector_db.name
}

output "pgvector_database_user" {
  description = "Database user for pgvector"
  value       = google_sql_user.pgvector_user.name
}

output "pgvector_database_password" {
  description = "Database password for pgvector"
  value       = google_sql_user.pgvector_user.password
  sensitive   = true
}

output "pgvector_database_url" {
  description = "PostgreSQL connection URL for pgvector"
  value = format(
    "postgresql://%s:%s@%s/%s",
    google_sql_user.pgvector_user.name,
    google_sql_user.pgvector_user.password,
    google_sql_database_instance.dify_pgvector.private_ip_address,
    google_sql_database.pgvector_db.name
  )
  sensitive = true
}

output "pgvector_replica_instance_name" {
  description = "Name of the pgvector read replica instance"
  value       = var.pgvector_enable_read_replica ? google_sql_database_instance.dify_pgvector_replica[0].name : null
}

output "pgvector_replica_private_ip" {
  description = "Private IP address of the pgvector read replica"
  value       = var.pgvector_enable_read_replica ? google_sql_database_instance.dify_pgvector_replica[0].private_ip_address : null
}

# =============================================================================
# Google Cloud Storage Outputs
# =============================================================================

output "gcs_bucket_name" {
  description = "Name of the GCS bucket"
  value       = google_storage_bucket.dify_storage.name
}

output "gcs_bucket_url" {
  description = "URL of the GCS bucket"
  value       = google_storage_bucket.dify_storage.url
}

output "gcs_bucket_self_link" {
  description = "Self link of the GCS bucket"
  value       = google_storage_bucket.dify_storage.self_link
}

output "service_account_email" {
  description = "Email of the Dify service account"
  value       = google_service_account.dify_sa.email
}

output "google_storage_service_account_json_base64" {
  description = "Base64-encoded service account JSON key for Google Storage access (only if create_service_account_key is true)"
  value       = var.create_service_account_key ? google_service_account_key.dify_sa_key[0].private_key : "Not created - VM uses default service account"
  sensitive   = true
}

# =============================================================================
# Redis Memorystore Outputs
# =============================================================================

output "redis_instance_name" {
  description = "Name of the Redis Memorystore instance"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].name : null
}

output "redis_host" {
  description = "Host (IP address) of the Redis instance"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].host : null
}

output "redis_port" {
  description = "Port of the Redis instance"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].port : null
}

output "redis_current_location_id" {
  description = "The current zone where the Redis instance is located"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].current_location_id : null
}

output "redis_read_endpoint" {
  description = "Read endpoint for the Redis instance (for read replicas)"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].read_endpoint : null
}

output "redis_read_endpoint_port" {
  description = "Port for the read endpoint"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].read_endpoint_port : null
}

output "redis_auth_string" {
  description = "Redis AUTH string (password)"
  value       = var.enable_redis && var.redis_auth_enabled ? google_redis_instance.dify_redis[0].auth_string : null
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis connection string (redis://host:port)"
  value = var.enable_redis ? format(
    "redis://%s:%d",
    google_redis_instance.dify_redis[0].host,
    google_redis_instance.dify_redis[0].port
  ) : null
}

output "redis_connection_url" {
  description = "Redis connection URL with authentication (if enabled)"
  value = var.enable_redis ? (
    var.redis_auth_enabled ? format(
      "redis://:%s@%s:%d",
      google_redis_instance.dify_redis[0].auth_string,
      google_redis_instance.dify_redis[0].host,
      google_redis_instance.dify_redis[0].port
      ) : format(
      "redis://%s:%d",
      google_redis_instance.dify_redis[0].host,
      google_redis_instance.dify_redis[0].port
    )
  ) : null
  sensitive = true
}

output "redis_persistence_iam_identity" {
  description = "Cloud IAM identity for RDB persistence"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].persistence_iam_identity : null
}

output "redis_server_ca_certs" {
  description = "List of server CA certificates for the instance"
  value       = var.enable_redis ? google_redis_instance.dify_redis[0].server_ca_certs : null
  sensitive   = true
}
