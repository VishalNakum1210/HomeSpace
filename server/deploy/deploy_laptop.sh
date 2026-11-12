#!/usr/bin/env bash
set -euo pipefail

echo "================================================="
echo "   HomeSpace Server Deployment (Xubuntu Laptop)  "
echo "================================================="

TARGET_DIR="${HOME}/homespace"
DATA_DIR="${HOME}/homespace-data"

echo "1. Creating data directory: ${DATA_DIR}..."
mkdir -p "${DATA_DIR}"
chmod 700 "${DATA_DIR}"

if [ ! -d "${TARGET_DIR}" ]; then
  echo "2. Cloning HomeSpace repository..."
  git clone https://github.com/VishalNakum1210/HomeSpace.git "${TARGET_DIR}"
else
  echo "2. Pulling latest updates from GitHub..."
  cd "${TARGET_DIR}"
  git fetch origin main
  git reset --hard origin/main
fi

cd "${TARGET_DIR}/server"

echo "3. Installing backend dependencies..."
corepack enable || true
corepack pnpm install

echo "4. Setting up .env configuration..."
cat <<EOF > .env
HOST=0.0.0.0
PORT=8888
DATA_DIR=${DATA_DIR}
NODE_ENV=production
# 10 GiB per user quota
DEFAULT_USER_QUOTA_BYTES=10737418240
EOF

echo "5. Starting / restarting service with PM2..."
if command -v pm2 &> /dev/null; then
  pm2 delete homespace 2>/dev/null || true
  pm2 start src/index.js --name homespace --time
  pm2 save
  echo "Server started via PM2."
else
  echo "PM2 not found, running with node in background..."
  nohup node src/index.js > homespace.log 2>&1 &
fi

echo "6. Verifying health check on port 8888..."
sleep 2
curl -s http://127.0.0.1:8888/api/health || {
  echo "Health check failed. Check homespace.log or pm2 logs homespace."
  exit 1
}

echo ""
echo "================================================="
echo "  SUCCESS! HomeSpace is running on port 8888     "
echo "  Local LAN URL: http://192.168.0.108:8888       "
echo "  Tailscale URL: http://100.113.105.20:8888      "
echo "================================================="
