#!/bin/bash

set -euo pipefail

# Configuration
SITE_NAME="chisamuel"
DOMAIN="chisamuel.com"
GITHUB_REPO="https://github.com/ChiSamuelA/chisamuel.git"
BRANCH="main"
DEPLOY_DIR="/var/www/sites/${SITE_NAME}"
TEMP_DIR=$(mktemp -d)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying ${DOMAIN}${NC}"
echo -e "${GREEN}========================================${NC}"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Step 1: Clone repository
echo -e "${YELLOW}[1/8] Cloning repository...${NC}"
cd "$TEMP_DIR"
git clone --depth 1 --branch "$BRANCH" "$GITHUB_REPO" site
cd site

# Step 2: Install dependencies
echo -e "${YELLOW}[2/8] Installing dependencies...${NC}"
npm ci --production=false

# Step 3: Build the site
echo -e "${YELLOW}[3/8] Building Next.js site...${NC}"
npm run build

# Check if build was successful
if [ ! -d "out" ] && [ ! -d ".next" ]; then
    echo -e "${RED}Build failed! No output directory found.${NC}"
    exit 1
fi

# Step 4: Create deployment directory
echo -e "${YELLOW}[4/8] Preparing deployment directory...${NC}"
sudo mkdir -p "$DEPLOY_DIR"
sudo chown -R deploy:deploy "$DEPLOY_DIR"

# Step 5: Deploy files
echo -e "${YELLOW}[5/8] Deploying files...${NC}"
if [ -d "out" ]; then
    echo "  -> Deploying static export..."
    rsync -av --delete out/ "$DEPLOY_DIR/"
elif [ -d ".next" ]; then
    echo "  -> Deploying SSR build..."
    rsync -av --delete --exclude 'node_modules' --exclude '.git' ./ "$DEPLOY_DIR/"
    cd "$DEPLOY_DIR"
    npm ci --production
fi

# Step 6: Set permissions
echo -e "${YELLOW}[6/8] Setting permissions...${NC}"
sudo chown -R deploy:www-data "$DEPLOY_DIR"
sudo chmod -R 755 "$DEPLOY_DIR"

# Step 7: Test Nginx
echo -e "${YELLOW}[7/8] Testing Nginx configuration...${NC}"
sudo nginx -t

# Step 8: Reload Nginx
echo -e "${YELLOW}[8/8] Reloading Nginx...${NC}"
sudo systemctl reload nginx

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${GREEN}Visit: https://${DOMAIN}${NC}"
echo -e "${GREEN}========================================${NC}"