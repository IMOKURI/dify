output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.dify_gke.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.dify_gke.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.dify_gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.dify_gke.location
}

output "postgres_connection_name" {
  description = "Cloud SQL PostgreSQL connection name"
  value       = google_sql_database_instance.dify_postgres.connection_name
}

output "postgres_private_ip" {
  description = "Cloud SQL PostgreSQL private IP"
  value       = google_sql_database_instance.dify_postgres.private_ip_address
}

output "redis_host" {
  description = "Redis instance host"
  value       = google_redis_instance.dify_redis.host
}

output "redis_port" {
  description = "Redis instance port"
  value       = google_redis_instance.dify_redis.port
}

output "storage_bucket_name" {
  description = "GCS bucket name for storage"
  value       = google_storage_bucket.dify_storage.name
}

output "storage_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.dify_storage.url
}

output "service_account_email" {
  description = "Service account email for GKE"
  value       = google_service_account.dify_gke_sa.email
}

output "vpc_network_name" {
  description = "VPC network name"
  value       = google_compute_network.dify_vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.dify_subnet.name
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.dify_gke.name} --region ${var.region} --project ${var.project_id}"
}
