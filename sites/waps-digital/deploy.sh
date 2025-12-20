#!/bin/bash

set -euo pipefail

# Configuration
SITE_NAME="waps-digital"
DOMAIN="waps-digital.cloud"
GITHUB_REPO="https://${GH_TOKEN}@github.com/Solumentics-Waps-Digital-Collaboration/waps-digital.git"
BRANCH="main"
DEPLOY_DIR="/var/www/sites/${SITE_NAME}"
SCRIPTS_DIR="/var/www/deployment-hub/sites/${SITE_NAME}"
TEMP_DIR=$(mktemp -d)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying ${DOMAIN} (Payload CMS)${NC}"
echo -e "${GREEN}========================================${NC}"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Step 1: Clone repository
echo -e "${YELLOW}[1/11] Cloning repository...${NC}"
cd "$TEMP_DIR"
git clone --depth 1 --branch "$BRANCH" "$GITHUB_REPO" site
cd site

# Step 2: Create deployment directory
echo -e "${YELLOW}[2/11] Preparing deployment directory...${NC}"
sudo mkdir -p "$DEPLOY_DIR"
sudo chown -R deploy:deploy "$DEPLOY_DIR"

# Step 3: Stop existing containers
echo -e "${YELLOW}[3/11] Stopping existing containers...${NC}"
if [ -d "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/docker-compose.prod.yml" ]; then
    cd "$DEPLOY_DIR"
    docker-compose -f docker-compose.prod.yml down || true
fi

# Step 4: Copy files to deployment directory
echo -e "${YELLOW}[4/11] Copying files...${NC}"
cd "$TEMP_DIR/site"
rsync -av --delete \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude '.next' \
    --exclude '.env' \
    --exclude 'docker-compose.prod.yml' \
    ./ "$DEPLOY_DIR/"

# Step 5: Copy custom Dockerfile
echo -e "${YELLOW}[5/11] Copying custom Dockerfile...${NC}"
if [ -f "$SCRIPTS_DIR/Dockerfile.prod" ]; then
    cp "$SCRIPTS_DIR/Dockerfile.prod" "$DEPLOY_DIR/Dockerfile.prod"
    echo "Custom Dockerfile.prod copied"
else
    echo -e "${RED}ERROR: Dockerfile.prod not found at $SCRIPTS_DIR/Dockerfile.prod${NC}"
    exit 1
fi

# Step 6: Create production docker-compose
echo -e "${YELLOW}[6/11] Creating production docker-compose...${NC}"
cd "$DEPLOY_DIR"
cat > docker-compose.prod.yml <<'EOF'
version: '3'

services:
  payload:
    build:
      context: .
      dockerfile: Dockerfile.prod
    ports:
      - '3000:3000'
    depends_on:
      - mongo
    env_file:
      - .env
    restart: unless-stopped
    volumes:
      - media_uploads:/app/public

  mongo:
    image: mongo:latest
    ports:
      - '27017:27017'
    command:
      - --storageEngine=wiredTiger
    volumes:
      - mongo_data:/data/db
    restart: unless-stopped

volumes:
  mongo_data:
  media_uploads:
EOF

# Step 7: Check for .env file
echo -e "${YELLOW}[7/11] Checking environment variables...${NC}"
if [ ! -f "$DEPLOY_DIR/.env" ]; then
    echo -e "${RED}ERROR: .env file not found!${NC}"
    echo -e "${YELLOW}Please create .env file at: $DEPLOY_DIR/.env${NC}"
    echo -e "${YELLOW}Required variables:${NC}"
    echo "DATABASE_URL=mongodb://mongo:27017/waps-digital"
    echo "PAYLOAD_SECRET=your-secret-key-here"
    echo "NEXT_PUBLIC_SERVER_URL=https://waps-digital.cloud"
    exit 1
fi

# Step 8: Build Docker image
echo -e "${YELLOW}[8/11] Building Docker image...${NC}"
docker-compose -f docker-compose.prod.yml build --no-cache

# Step 9: Start containers
echo -e "${YELLOW}[9/11] Starting containers...${NC}"
docker-compose -f docker-compose.prod.yml up -d

# Step 10: Wait for app to be ready
echo -e "${YELLOW}[10/11] Waiting for application to start...${NC}"
sleep 15

# Check if containers are running
if ! docker-compose -f docker-compose.prod.yml ps | grep -q "Up"; then
    echo -e "${RED}ERROR: Containers failed to start!${NC}"
    docker-compose -f docker-compose.prod.yml logs --tail=100
    exit 1
fi

# Step 11: Test application
echo -e "${YELLOW}[11/11] Testing application...${NC}"
MAX_RETRIES=12
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        echo -e "${GREEN}Application is responding!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for application... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${YELLOW}Warning: Application may still be starting up...${NC}"
    echo -e "${YELLOW}Check logs with: docker-compose -f docker-compose.prod.yml logs${NC}"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${GREEN}Docker containers running${NC}"
echo -e "${GREEN}Visit: https://${DOMAIN}${NC}"
echo -e "${GREEN}Admin: https://${DOMAIN}/admin${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Container status:${NC}"
docker-compose -f docker-compose.prod.yml ps