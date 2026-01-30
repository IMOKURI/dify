#!/bin/bash
# Pre-deployment validation script for Dify on GCP

set -e

echo "=== Dify GCP Deployment Pre-check ==="
echo ""

# Check if required tools are installed
echo "Checking required tools..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform 1.0 or later."
    exit 1
fi
echo "✅ Terraform is installed: $(terraform version -json | jq -r '.terraform_version')"

if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed. Please install Google Cloud SDK."
    exit 1
fi
echo "✅ gcloud CLI is installed: $(gcloud version | grep 'Google Cloud SDK' | awk '{print $4}')"

if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. Please install jq for JSON processing."
    exit 1
fi
echo "✅ jq is installed"

echo ""

# Check if authenticated with GCP
echo "Checking GCP authentication..."
if ! gcloud auth application-default print-access-token &> /dev/null; then
    echo "❌ Not authenticated with GCP. Please run: gcloud auth application-default login"
    exit 1
fi
echo "✅ Authenticated with GCP"

echo ""

# Check if terraform.tfvars exists
echo "Checking configuration files..."
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found. Please copy terraform.tfvars.example and configure it."
    exit 1
fi
echo "✅ terraform.tfvars exists"

echo ""

# Extract project_id from terraform.tfvars
PROJECT_ID=$(grep '^project_id' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')

if [ -z "$PROJECT_ID" ]; then
    echo "❌ project_id is not set in terraform.tfvars"
    exit 1
fi

echo "Project ID: $PROJECT_ID"
echo ""

# Check if required GCP APIs are enabled
echo "Checking required GCP APIs..."

REQUIRED_APIS=(
    "compute.googleapis.com"
    "sqladmin.googleapis.com"
    "redis.googleapis.com"
    "storage-api.googleapis.com"
    "servicenetworking.googleapis.com"
    "iam.googleapis.com"
)

MISSING_APIS=()

for api in "$${REQUIRED_APIS[@]}"; do
    if gcloud services list --enabled --project=$PROJECT_ID --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        echo "✅ $api is enabled"
    else
        echo "❌ $api is NOT enabled"
        MISSING_APIS+=("$api")
    fi
done

if [ $${#MISSING_APIS[@]} -gt 0 ]; then
    echo ""
    echo "The following APIs need to be enabled:"
    for api in "$${MISSING_APIS[@]}"; do
        echo "  - $api"
    done
    echo ""
    echo "To enable all required APIs, run:"
    echo "gcloud services enable $${REQUIRED_APIS[@]} --project=$PROJECT_ID"
    exit 1
fi

echo ""

# Check for sensitive values
echo "Checking sensitive configuration values..."

WARNINGS=0

if grep -q 'db_password.*=.*"your-secure-password-here"' terraform.tfvars; then
    echo "⚠️  WARNING: db_password is set to the default value. Please change it!"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -q 'pgvector_password.*=.*"your-secure-password-here"' terraform.tfvars; then
    echo "⚠️  WARNING: pgvector_password is set to the default value. Please change it!"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -q 'secret_key.*=.*"your-secret-key-here"' terraform.tfvars; then
    echo "⚠️  WARNING: secret_key is set to the default value. Please change it!"
    echo "   Generate a new key with: openssl rand -base64 42"
    WARNINGS=$((WARNINGS + 1))
fi

if [ $WARNINGS -eq 0 ]; then
    echo "✅ No sensitive configuration warnings"
else
    echo ""
    echo "⚠️  Found $WARNINGS warning(s). Please review and update the values before deployment."
fi

echo ""

# Check quotas (optional, requires additional permissions)
echo "=== Pre-check Complete ==="
echo ""
echo "Next steps:"
echo "1. Review terraform.tfvars and ensure all values are correct"
echo "2. Run: terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
echo ""
