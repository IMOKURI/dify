variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-northeast1-a"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "dify"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "machine_type" {
  description = "Machine type for the VM instance"
  type        = string
  default     = "n1-standard-2"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # 本番環境では制限することを推奨
}

variable "ssh_user" {
  description = "SSH user name"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for SSL certificate (leave empty to use self-signed certificate)"
  type        = string
  default     = ""
}

variable "ssl_certificate" {
  description = "Self-signed SSL certificate (PEM format, required if domain_name is empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_private_key" {
  description = "Self-signed SSL private key (PEM format, required if domain_name is empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "docker_compose_version" {
  description = "Docker Compose version to install"
  type        = string
  default     = "v2.24.5"
}

# Cloud SQL Variables
variable "cloudsql_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-7680" # 2 vCPU, 7.5GB RAM
}

variable "cloudsql_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 50
}

variable "cloudsql_database_version" {
  description = "PostgreSQL version for Cloud SQL"
  type        = string
  default     = "POSTGRES_15"
}

variable "cloudsql_backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "cloudsql_backup_start_time" {
  description = "Backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "dify"
}

variable "db_user" {
  description = "Database user name"
  type        = string
  default     = "dify"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
