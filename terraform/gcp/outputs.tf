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
# pgvector Outputs (when enabled)
# =============================================================================

output "pgvector_instance_name" {
  description = "Name of the pgvector Cloud SQL instance"
  value       = var.enable_pgvector ? google_sql_database_instance.dify_pgvector[0].name : null
}

output "pgvector_connection_name" {
  description = "Connection name for the pgvector Cloud SQL instance"
  value       = var.enable_pgvector ? google_sql_database_instance.dify_pgvector[0].connection_name : null
}

output "pgvector_private_ip" {
  description = "Private IP address of the pgvector Cloud SQL instance"
  value       = var.enable_pgvector ? google_sql_database_instance.dify_pgvector[0].private_ip_address : null
}

output "pgvector_public_ip" {
  description = "Public IP address of the pgvector Cloud SQL instance (if enabled)"
  value       = var.enable_pgvector && var.pgvector_enable_public_ip ? google_sql_database_instance.dify_pgvector[0].public_ip_address : null
}

output "pgvector_database_name" {
  description = "Database name for pgvector"
  value       = var.enable_pgvector ? google_sql_database.pgvector_db[0].name : null
}

output "pgvector_database_user" {
  description = "Database user for pgvector"
  value       = var.enable_pgvector ? google_sql_user.pgvector_user[0].name : null
}

output "pgvector_database_password" {
  description = "Database password for pgvector"
  value       = var.enable_pgvector ? google_sql_user.pgvector_user[0].password : null
  sensitive   = true
}

output "pgvector_database_url" {
  description = "PostgreSQL connection URL for pgvector"
  value = var.enable_pgvector ? format(
    "postgresql://%s:%s@%s/%s",
    google_sql_user.pgvector_user[0].name,
    google_sql_user.pgvector_user[0].password,
    google_sql_database_instance.dify_pgvector[0].private_ip_address,
    google_sql_database.pgvector_db[0].name
  ) : null
  sensitive = true
}

output "pgvector_replica_instance_name" {
  description = "Name of the pgvector read replica instance"
  value       = var.enable_pgvector && var.pgvector_enable_read_replica ? google_sql_database_instance.dify_pgvector_replica[0].name : null
}

output "pgvector_replica_private_ip" {
  description = "Private IP address of the pgvector read replica"
  value       = var.enable_pgvector && var.pgvector_enable_read_replica ? google_sql_database_instance.dify_pgvector_replica[0].private_ip_address : null
}
