#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}VPS Initial Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
sudo apt update
sudo apt upgrade -y

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
sudo apt install -y git nginx curl build-essential

# Install Node.js 20.x (LTS)
echo -e "${YELLOW}Installing Node.js...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# Verify installations
echo -e "${YELLOW}Verifying installations...${NC}"
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "Nginx version: $(nginx -v 2>&1)"

# Create deployment directories
echo -e "${YELLOW}Creating deployment directories...${NC}"
sudo mkdir -p /var/www/deployment-hub
sudo mkdir -p /var/www/sites
sudo chown -R deploy:deploy /var/www/deployment-hub
sudo chown -R deploy:deploy /var/www/sites

# Configure sudo permissions for deploy user
echo -e "${YELLOW}Configuring sudo permissions...${NC}"
sudo tee /etc/sudoers.d/deploy-nginx > /dev/null <<EOF
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(ALL) NOPASSWD: /usr/bin/nginx -t
deploy ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p /var/www/sites/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/chown -R deploy\:deploy /var/www/sites/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/chown -R deploy\:www-data /var/www/sites/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/chmod -R * /var/www/sites/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/cp * /etc/nginx/sites-available/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/ln -s /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*
deploy ALL=(ALL) NOPASSWD: /usr/bin/rm /etc/nginx/sites-enabled/*
EOF
sudo chmod 0440 /etc/sudoers.d/deploy-nginx

# Remove default Nginx site
echo -e "${YELLOW}Removing default Nginx site...${NC}"
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx
echo -e "${YELLOW}Testing Nginx configuration...${NC}"
sudo nginx -t

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ VPS Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Clone deployment-hub repo to /var/www/deployment-hub"
echo -e "2. Run site-specific deployment scripts"
echo -e "3. Setup SSL certificates"