#!/bin/bash

set -euo pipefail

# Configuration
SITE_NAME="waps-digital"
DOMAIN="wapsdigital.cloud"
GITHUB_REPO="https://${GH_TOKEN}@github.com/Solumentics-Waps-Digital-Collaboration/waps-digital.git"
BRANCH="main"
DEPLOY_DIR="/var/www/sites/${SITE_NAME}"
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

# Step 2: Create deployment directory and persistent storage
echo -e "${YELLOW}[2/11] Preparing deployment directory and storage...${NC}"
sudo mkdir -p "$DEPLOY_DIR"
sudo mkdir -p "$DEPLOY_DIR/uploads/media"  # Persistent uploads
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
    --exclude 'uploads' \
    ./ "$DEPLOY_DIR/"

# Step 5: Create production docker-compose with BULLETPROOF config
echo -e "${YELLOW}[5/11] Creating production docker-compose...${NC}"
cd "$DEPLOY_DIR"
cat > docker-compose.prod.yml <<'EOF'
version: '3.8'

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
      - ./uploads/media:/app/public/media  # PERSISTENT uploads!
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1024M
        reservations:
          cpus: '0.5'
          memory: 512M
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s

  mongo:
    image: mongo:7
    ports:
      - '27017:27017'
    command:
      - --storageEngine=wiredTiger
    volumes:
      - mongo_data:/data/db
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.75'
          memory: 768M
        reservations:
          cpus: '0.25'
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "echo 'db.runCommand(\"ping\").ok' | mongosh localhost:27017/test --quiet || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 40s

volumes:
  mongo_data:
EOF

# Step 6: Check for .env file
echo -e "${YELLOW}[6/11] Checking environment variables...${NC}"
if [ ! -f "$DEPLOY_DIR/.env" ]; then
    echo -e "${RED}ERROR: .env file not found!${NC}"
    echo -e "${YELLOW}Please create .env file at: $DEPLOY_DIR/.env${NC}"
    echo -e "${YELLOW}Required variables:${NC}"
    echo "DATABASE_URI=mongodb://mongo:27017/waps-digital"
    echo "PAYLOAD_SECRET=your-secret-key-here"
    echo "NEXT_PUBLIC_SERVER_URL=https://wapsdigital.cloud"
    exit 1
fi

# Step 7: Build Docker image (with lower priority to not crash server)
echo -e "${YELLOW}[7/11] Building Docker image (this may take 5-10 minutes)...${NC}"
nice -n 19 docker-compose -f docker-compose.prod.yml build --no-cache

# Step 8: Start containers
echo -e "${YELLOW}[8/11] Starting containers...${NC}"
docker-compose -f docker-compose.prod.yml up -d

# Step 9: Wait for MongoDB to be ready
echo -e "${YELLOW}[9/11] Waiting for MongoDB to be ready...${NC}"
sleep 15

# Step 10: Wait for Payload to be ready
echo -e "${YELLOW}[10/11] Waiting for Payload CMS to start...${NC}"
MAX_RETRIES=20
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        echo -e "${GREEN}Payload CMS is responding!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for Payload CMS... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${YELLOW}Warning: Payload CMS may still be starting up...${NC}"
fi

# Step 11: Reload Nginx
echo -e "${YELLOW}[11/11] Reloading Nginx...${NC}"
sudo nginx -t
sudo systemctl reload nginx

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Payload CMS is running with:${NC}"
echo -e "${GREEN}- Persistent uploads storage${NC}"
echo -e "${GREEN}- Health checks enabled${NC}"
echo -e "${GREEN}- CPU/Memory limits (1 core, 1GB)${NC}"
echo -e "${GREEN}- MongoDB with health monitoring${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Website: https://${DOMAIN}${NC}"
echo -e "${GREEN}Admin: https://${DOMAIN}/admin${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Container status:${NC}"
docker-compose -f docker-compose.prod.yml ps