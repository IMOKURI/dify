# Google Cloud Storage bucket for file storage
resource "google_storage_bucket" "dify_storage" {
  name          = "dify-storage-${var.project_id}-${var.environment}"
  location      = var.storage_bucket_location
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

# IAM binding for GKE service account to access bucket
resource "google_storage_bucket_iam_member" "dify_storage_admin" {
  bucket = google_storage_bucket.dify_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dify_gke_sa.email}"
}
