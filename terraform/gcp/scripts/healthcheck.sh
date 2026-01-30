#!/bin/bash
# Post-deployment monitoring and health check script for Dify on GCP

set -e

echo "=== Dify GCP Deployment Health Check ==="
echo ""

# Get outputs from Terraform
echo "Retrieving deployment information..."

LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
HTTP_URL=$(terraform output -raw access_url_http 2>/dev/null || echo "")

if [ -z "$LB_IP" ]; then
    echo "❌ Unable to retrieve load balancer IP. Run 'terraform apply' first."
    exit 1
fi

echo "Load Balancer IP: $LB_IP"
echo "Access URL: $HTTP_URL"
echo ""

# Check load balancer health
echo "Checking load balancer health..."
sleep 5

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$HTTP_URL/health" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Load balancer is healthy (HTTP $HTTP_STATUS)"
else
    echo "❌ Load balancer health check failed (HTTP $HTTP_STATUS)"
    echo "   This is normal if instances are still starting up."
    echo "   Wait a few minutes and try again."
fi

echo ""

# Get instance group information
echo "Checking managed instance group..."

PROJECT_ID=$(terraform output -json | jq -r '.vpc_network_name.value' | cut -d'/' -f1 || grep '^project_id' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
REGION=$(grep '^region' terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo "asia-northeast1")
MIG_NAME=$(terraform output -raw instance_group_manager_name 2>/dev/null || echo "")

if [ -n "$MIG_NAME" ]; then
    echo "Instance Group: $MIG_NAME"
    
    # Get instance count
    INSTANCE_COUNT=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    echo "Number of instances: $INSTANCE_COUNT"
    
    # Get instance status
    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo ""
        echo "Instance status:"
        gcloud compute instance-groups managed list-instances "$MIG_NAME" \
            --region="$REGION" \
            --format="table(name,status,instanceStatus,currentAction)" 2>/dev/null || echo "Unable to retrieve instance status"
    fi
else
    echo "⚠️  Unable to retrieve managed instance group name"
fi

echo ""

# Check Cloud SQL instances
echo "Checking Cloud SQL instances..."

POSTGRES_MAIN=$(terraform output -raw postgres_main_connection_name 2>/dev/null || echo "")
POSTGRES_VECTOR=$(terraform output -raw postgres_vector_connection_name 2>/dev/null || echo "")

if [ -n "$POSTGRES_MAIN" ]; then
    MAIN_STATUS=$(gcloud sql instances describe "$POSTGRES_MAIN" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    echo "Main Database: $POSTGRES_MAIN - Status: $MAIN_STATUS"
fi

if [ -n "$POSTGRES_VECTOR" ]; then
    VECTOR_STATUS=$(gcloud sql instances describe "$POSTGRES_VECTOR" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    echo "Vector Database: $POSTGRES_VECTOR - Status: $VECTOR_STATUS"
fi

echo ""

# Check Redis instance
echo "Checking Redis instance..."

REDIS_NAME=$(gcloud redis instances list --format="value(name)" --filter="name~dify" 2>/dev/null | head -1 || echo "")

if [ -n "$REDIS_NAME" ]; then
    REDIS_STATUS=$(gcloud redis instances describe "$REDIS_NAME" --region="$REGION" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    echo "Redis: $REDIS_NAME - Status: $REDIS_STATUS"
else
    echo "⚠️  Unable to find Redis instance"
fi

echo ""

# Check Cloud Storage bucket
echo "Checking Cloud Storage bucket..."

BUCKET_NAME=$(terraform output -raw storage_bucket_name 2>/dev/null || echo "")

if [ -n "$BUCKET_NAME" ]; then
    if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        echo "✅ Storage bucket exists: $BUCKET_NAME"
    else
        echo "❌ Storage bucket not accessible: $BUCKET_NAME"
    fi
else
    echo "⚠️  Unable to retrieve storage bucket name"
fi

echo ""

# Summary
echo "=== Health Check Complete ==="
echo ""
echo "Next steps:"
echo "1. Access your Dify instance at: $HTTP_URL"
echo "2. Configure DNS to point to: $LB_IP"
echo "3. Set up HTTPS with SSL certificate (if not already done)"
echo "4. Monitor logs in Cloud Logging"
echo ""
echo "Useful commands:"
echo "  - View instances: gcloud compute instances list --filter='name~dify'"
echo "  - SSH to instance: gcloud compute ssh INSTANCE_NAME"
echo "  - View logs: gcloud logging read 'resource.type=gce_instance' --limit 50"
echo ""
