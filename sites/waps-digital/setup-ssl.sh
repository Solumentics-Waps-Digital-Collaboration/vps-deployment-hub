#!/bin/bash

set -euo pipefail

# Configuration
DOMAIN="wapsdigital.cloud"
EMAIL="your-email@example.com"  # CHANGE THIS TO YOUR EMAIL

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setting up SSL for ${DOMAIN}${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Installing Certbot...${NC}"
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

# Obtain SSL certificate
echo -e "${YELLOW}Obtaining SSL certificate...${NC}"
sudo certbot --nginx \
    -d "$DOMAIN" \
    -d "www.$DOMAIN" \
    --non-interactive \
    --agree-tos \
    -m "$EMAIL" \
    --redirect

# Test automatic renewal
echo -e "${YELLOW}Testing automatic renewal...${NC}"
sudo certbot renew --dry-run

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSL Certificate Installed!${NC}"
echo -e "${GREEN}HTTPS enabled for ${DOMAIN}${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Certificate will auto-renew every 90 days${NC}"