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

echo "Setup completed successfully!" > /var/log/startup-script.log