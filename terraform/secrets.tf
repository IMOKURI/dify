# Secret Manager secrets
resource "google_secret_manager_secret" "db_password" {
  secret_id = "dify-db-password-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret" "secret_key" {
  secret_id = "dify-secret-key-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret_key" {
  secret      = google_secret_manager_secret.secret_key.id
  secret_data = var.secret_key
}

resource "google_secret_manager_secret" "sandbox_api_key" {
  secret_id = "dify-sandbox-api-key-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "sandbox_api_key" {
  secret      = google_secret_manager_secret.sandbox_api_key.id
  secret_data = var.sandbox_api_key
}

resource "google_secret_manager_secret" "weaviate_api_key" {
  secret_id = "dify-weaviate-api-key-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "weaviate_api_key" {
  secret      = google_secret_manager_secret.weaviate_api_key.id
  secret_data = var.weaviate_api_key
}

# IAM binding for GKE service account to access secrets
resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dify_gke_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "secret_key_access" {
  secret_id = google_secret_manager_secret.secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dify_gke_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "sandbox_api_key_access" {
  secret_id = google_secret_manager_secret.sandbox_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dify_gke_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "weaviate_api_key_access" {
  secret_id = google_secret_manager_secret.weaviate_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dify_gke_sa.email}"
}
