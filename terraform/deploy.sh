#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v terraform &> /dev/null; then
        missing_deps+=("terraform")
    fi
    
    if ! command -v gcloud &> /dev/null; then
        missing_deps+=("gcloud")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_error "Please install them before continuing."
        exit 1
    fi
    
    print_info "All dependencies are installed."
}

# Check if terraform.tfvars exists
check_tfvars() {
    if [ ! -f "terraform.tfvars" ]; then
        print_error "terraform.tfvars not found!"
        print_info "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        print_warning "Please edit terraform.tfvars with your project-specific values before continuing."
        exit 1
    fi
}

# Enable required GCP APIs
enable_gcp_apis() {
    print_info "Enabling required GCP APIs..."
    
    local project_id=$(grep 'project_id' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')
    
    if [ -z "$project_id" ]; then
        print_error "Could not determine project_id from terraform.tfvars"
        exit 1
    fi
    
    gcloud config set project "$project_id"
    
    local apis=(
        "compute.googleapis.com"
        "container.googleapis.com"
        "sqladmin.googleapis.com"
        "redis.googleapis.com"
        "secretmanager.googleapis.com"
        "servicenetworking.googleapis.com"
        "storage-api.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_info "Enabling $api..."
        gcloud services enable "$api" --project="$project_id"
    done
    
    print_info "All required APIs are enabled."
}

# Initialize and apply Terraform
deploy_infrastructure() {
    print_info "Initializing Terraform..."
    terraform init
    
    print_info "Validating Terraform configuration..."
    terraform validate
    
    print_info "Planning Terraform changes..."
    terraform plan -out=tfplan
    
    read -p "Do you want to apply these changes? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
    
    print_info "Applying Terraform configuration..."
    terraform apply tfplan
    rm -f tfplan
    
    print_info "Infrastructure deployment completed!"
}

# Configure kubectl
configure_kubectl() {
    print_info "Configuring kubectl..."
    
    local cluster_name=$(terraform output -raw gke_cluster_name)
    local cluster_location=$(terraform output -raw gke_cluster_location)
    local project_id=$(grep 'project_id' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')
    
    gcloud container clusters get-credentials "$cluster_name" \
        --region "$cluster_location" \
        --project "$project_id"
    
    print_info "kubectl configured successfully!"
}

# Deploy Kubernetes resources
deploy_kubernetes() {
    print_info "Deploying Kubernetes resources..."
    
    # Get Terraform outputs
    local postgres_host=$(terraform output -raw postgres_private_ip)
    local redis_host=$(terraform output -raw redis_host)
    local redis_port=$(terraform output -raw redis_port)
    local bucket_name=$(terraform output -raw storage_bucket_name)
    
    # Create namespace
    print_info "Creating namespace..."
    kubectl apply -f k8s/namespace.yaml
    
    # Create database config
    print_info "Creating database configuration..."
    kubectl create configmap dify-db-config \
        --from-literal=DB_HOST="$postgres_host" \
        --from-literal=REDIS_HOST="$redis_host" \
        --from-literal=REDIS_PORT="$redis_port" \
        --namespace=dify \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply other resources
    print_info "Applying ServiceAccount and RBAC..."
    kubectl apply -f k8s/serviceaccount.yaml
    
    print_info "Applying ConfigMap..."
    kubectl apply -f k8s/configmap.yaml
    
    print_info "Applying Secrets..."
    # Update bucket name in secrets
    sed "s/CHANGE_ME_BUCKET_NAME/$bucket_name/g" k8s/secrets.yaml | kubectl apply -f -
    
    print_info "Applying Persistent Volumes..."
    kubectl apply -f k8s/persistent-volumes.yaml
    
    print_info "Deploying Weaviate..."
    kubectl apply -f k8s/weaviate-statefulset.yaml
    
    print_info "Deploying SSRF Proxy..."
    kubectl apply -f k8s/ssrf-proxy-deployment.yaml
    
    print_info "Deploying Sandbox..."
    kubectl apply -f k8s/sandbox-deployment.yaml
    
    print_info "Deploying Plugin Daemon..."
    kubectl apply -f k8s/plugin-daemon-deployment.yaml
    
    print_info "Deploying API..."
    kubectl apply -f k8s/api-deployment.yaml
    
    print_info "Deploying Workers..."
    kubectl apply -f k8s/worker-deployment.yaml
    
    print_info "Deploying Web..."
    kubectl apply -f k8s/web-deployment.yaml
    
    print_warning "Ingress deployment skipped. Please update k8s/ingress.yaml with your domain and apply manually."
    
    print_info "Kubernetes resources deployed successfully!"
}

# Wait for pods to be ready
wait_for_pods() {
    print_info "Waiting for pods to be ready..."
    
    kubectl wait --for=condition=ready pod \
        --all \
        --namespace=dify \
        --timeout=600s || true
    
    print_info "Checking pod status..."
    kubectl get pods -n dify
}

# Main deployment flow
main() {
    echo "======================================"
    echo "  Dify GCP Deployment Script"
    echo "======================================"
    echo
    
    check_dependencies
    check_tfvars
    
    read -p "Do you want to enable GCP APIs? (yes/no): " enable_apis
    if [ "$enable_apis" = "yes" ]; then
        enable_gcp_apis
    fi
    
    read -p "Do you want to deploy infrastructure with Terraform? (yes/no): " deploy_infra
    if [ "$deploy_infra" = "yes" ]; then
        deploy_infrastructure
    fi
    
    read -p "Do you want to configure kubectl? (yes/no): " config_kubectl
    if [ "$config_kubectl" = "yes" ]; then
        configure_kubectl
    fi
    
    read -p "Do you want to deploy Kubernetes resources? (yes/no): " deploy_k8s
    if [ "$deploy_k8s" = "yes" ]; then
        deploy_kubernetes
        wait_for_pods
    fi
    
    echo
    print_info "Deployment completed!"
    echo
    print_info "Next steps:"
    echo "  1. Update k8s/ingress.yaml with your domain name"
    echo "  2. Reserve a static IP: gcloud compute addresses create dify-static-ip --global"
    echo "  3. Point your domain to the static IP"
    echo "  4. Apply ingress: kubectl apply -f k8s/ingress.yaml"
    echo "  5. Monitor deployment: kubectl get pods -n dify -w"
    echo
    print_info "To get cluster credentials:"
    echo "  $(terraform output -raw kubectl_config_command)"
}

# Run main function
main
