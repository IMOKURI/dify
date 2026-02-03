#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Docker Compose
DOCKER_COMPOSE_VERSION="${docker_compose_version}"
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create docker-compose symlink
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Enable Docker service
systemctl enable docker
systemctl start docker

# Install additional tools
apt-get install -y git curl wget vim nano htop

# Create working directory
mkdir -p /opt/dify
chown ubuntu:ubuntu /opt/dify

# Install Nginx for reverse proxy (optional)
apt-get install -y nginx

# Configure Nginx as reverse proxy
cat > /etc/nginx/sites-available/dify << 'EOF'
server {
    listen 1080;
    server_name _;

    client_max_body_size 100M;

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass http://localhost:80;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/dify /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t
systemctl enable nginx
systemctl restart nginx

# Create startup instructions
cat > /opt/dify/README.md << 'EOF'
# Dify Deployment Instructions

## Deploy Dify

**Note:** Dify source code has been automatically downloaded and placed in `/opt/dify`.

1. Navigate to the Dify docker directory:
   ```bash
   cd /opt/dify/docker
   ```

2. Copy and configure environment variables:
   ```bash
   # Use the pre-configured .env.example if available
   cp /opt/dify/.env.example .env
   
   # Or use the default from Dify repository
   # cp .env.example .env
   
   # Edit .env file with your configuration
   nano .env
   ```

3. Start Dify with Docker Compose:
   ```bash
   docker-compose up -d
   ```

4. Check the status:
   ```bash
   docker-compose ps
   docker-compose logs -f
   ```

## Useful Commands

- Stop services: `docker-compose down`
- View logs: `docker-compose logs -f [service_name]`
- Restart services: `docker-compose restart`
- Update Dify to a new version:
  ```bash
  cd /opt/dify
  # Download new version (replace X.Y.Z with desired version)
  curl -L https://github.com/langgenius/dify/archive/refs/tags/X.Y.Z.tar.gz -o dify-X.Y.Z.tar.gz
  tar -xzf dify-X.Y.Z.tar.gz
  cp -r dify-X.Y.Z/* .
  rm -rf dify-X.Y.Z dify-X.Y.Z.tar.gz
  cd docker
  docker-compose pull
  docker-compose up -d
  ```

## Access

The application will be available at the Load Balancer IP address.
EOF

chown -R ubuntu:ubuntu /opt/dify

echo "Setup completed successfully!" > /var/log/startup-script.log
