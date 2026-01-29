variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "The GCP zone for resources"
  type        = string
  default     = "asia-northeast1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "production"
}

# Database configurations
variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-4096" # 2 vCPU, 4GB RAM
}

variable "db_availability_type" {
  description = "Cloud SQL availability type (REGIONAL or ZONAL)"
  type        = string
  default     = "REGIONAL"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "difyai123456"
}

# Redis configurations
variable "redis_memory_size_gb" {
  description = "Memory size in GB for Redis instance"
  type        = number
  default     = 1
}

variable "redis_tier" {
  description = "Redis tier (BASIC or STANDARD_HA)"
  type        = string
  default     = "BASIC"
}

# GKE configurations
variable "gke_node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 3
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4" # 4 vCPU, 16GB RAM
}

variable "gke_disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 100
}

variable "gke_min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}

variable "gke_max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
}

# Storage
variable "storage_bucket_location" {
  description = "Location for GCS bucket"
  type        = string
  default     = "ASIA"
}

variable "storage_class" {
  description = "Storage class for GCS bucket"
  type        = string
  default     = "STANDARD"
}

# Network
variable "network_cidr" {
  description = "CIDR range for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pod_cidr" {
  description = "CIDR range for GKE pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "service_cidr" {
  description = "CIDR range for GKE services"
  type        = string
  default     = "10.2.0.0/16"
}

# Domain and SSL
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = ""
}

# Secret keys
variable "secret_key" {
  description = "Application secret key"
  type        = string
  sensitive   = true
  default     = "sk-9f73s3ljTXVcMT3Blb3ljTqtsKiGHXVcMT3BlbkFJLK7U"
}

variable "sandbox_api_key" {
  description = "Sandbox API key"
  type        = string
  sensitive   = true
  default     = "dify-sandbox"
}

variable "weaviate_api_key" {
  description = "Weaviate API key"
  type        = string
  sensitive   = true
  default     = "WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih"
}
