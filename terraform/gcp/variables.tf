variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "asia-northeast1"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "dify"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "ssh_source_ranges" {
  description = "Source IP ranges allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Database configuration
variable "db_tier" {
  description = "Cloud SQL tier for main database"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_availability_type" {
  description = "Availability type for Cloud SQL (ZONAL or REGIONAL)"
  type        = string
  default     = "REGIONAL"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_database" {
  description = "Database name"
  type        = string
  default     = "dify"
}

variable "postgres_max_connections" {
  description = "Maximum number of connections for PostgreSQL"
  type        = string
  default     = "100"
}

# Vector database configuration
variable "vector_db_tier" {
  description = "Cloud SQL tier for vector database"
  type        = string
  default     = "db-custom-2-7680"
}

variable "pgvector_user" {
  description = "pgvector database username"
  type        = string
  default     = "postgres"
}

variable "pgvector_password" {
  description = "pgvector database password"
  type        = string
  sensitive   = true
}

variable "pgvector_database" {
  description = "pgvector database name"
  type        = string
  default     = "dify"
}

# Redis configuration
variable "redis_tier" {
  description = "Redis tier (BASIC or STANDARD_HA)"
  type        = string
  default     = "STANDARD_HA"
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}

# Storage configuration
variable "bucket_force_destroy" {
  description = "Allow destroying the bucket with objects"
  type        = bool
  default     = false
}

# Compute Engine configuration
variable "instance_type" {
  description = "Machine type for Compute Engine instances"
  type        = string
  default     = "e2-standard-4"
}

variable "instance_image" {
  description = "OS image for Compute Engine instances"
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

variable "instance_disk_size" {
  description = "Disk size in GB for Compute Engine instances"
  type        = number
  default     = 50
}

variable "instance_count" {
  description = "Number of Compute Engine instances"
  type        = number
  default     = 2
}

# Autoscaling configuration
variable "enable_autoscaling" {
  description = "Enable autoscaling for managed instance group"
  type        = bool
  default     = true
}

variable "autoscaling_min_replicas" {
  description = "Minimum number of instances for autoscaling"
  type        = number
  default     = 2
}

variable "autoscaling_max_replicas" {
  description = "Maximum number of instances for autoscaling"
  type        = number
  default     = 10
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 0.7
}

# Dify application configuration
variable "secret_key" {
  description = "Secret key for Dify application"
  type        = string
  sensitive   = true
}

variable "init_password" {
  description = "Initial admin password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "console_api_url" {
  description = "Console API URL"
  type        = string
  default     = ""
}

variable "console_web_url" {
  description = "Console Web URL"
  type        = string
  default     = ""
}

variable "service_api_url" {
  description = "Service API URL"
  type        = string
  default     = ""
}

variable "app_api_url" {
  description = "App API URL"
  type        = string
  default     = ""
}

variable "app_web_url" {
  description = "App Web URL"
  type        = string
  default     = ""
}

variable "files_url" {
  description = "Files URL"
  type        = string
  default     = ""
}

variable "dify_version" {
  description = "Dify Docker image version"
  type        = string
  default     = "1.11.4"
}

variable "log_level" {
  description = "Log level for Dify application"
  type        = string
  default     = "INFO"
}

# HTTPS configuration
variable "enable_https" {
  description = "Enable HTTPS for load balancer"
  type        = bool
  default     = false
}

variable "ssl_certificate" {
  description = "SSL certificate for HTTPS"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_private_key" {
  description = "SSL private key for HTTPS"
  type        = string
  default     = ""
  sensitive   = true
}

# Deletion protection
variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instances"
  type        = bool
  default     = true
}
