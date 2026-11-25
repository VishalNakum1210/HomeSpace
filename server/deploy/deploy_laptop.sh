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
if command -v pnpm &> /dev/null; then
  pnpm install
elif command -v corepack &> /dev/null; then
  corepack enable || true
  corepack pnpm install || npm install
else
  npm install
fi

echo "4. Setting up .env configuration..."
umask 077
cat <<EOF > .env
HOST=0.0.0.0
PORT=8888
DATA_DIR=${DATA_DIR}
NODE_ENV=production
# 10 GiB per user default quota
DEFAULT_USER_QUOTA_BYTES=10737418240
# Set to false after creating family accounts to lock down public signup
REGISTRATION_OPEN=true
EOF
chmod 600 .env

echo "5. Checking Xubuntu lid-close settings (Keep server alive with closed lid)..."
if grep -q "^HandleLidSwitch=ignore" /etc/systemd/logind.conf 2>/dev/null; then
  echo "✓ Lid-close sleep is already disabled (HandleLidSwitch=ignore)."
else
  echo "Tip: Run 'sudo sed -i \"s/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/\" /etc/systemd/logind.conf && sudo systemctl restart systemd-logind' to keep the server running with lid closed."
fi

echo "6. Starting / restarting service with PM2..."
if command -v pm2 &> /dev/null; then
  pm2 delete homespace 2>/dev/null || true
  pm2 start src/index.js --name homespace --time
  pm2 save
  echo "Server started via PM2."
else
  echo "PM2 not found, running with node in background..."
  nohup node src/index.js > homespace.log 2>&1 &
fi

echo "7. Verifying health check on port 8888..."
sleep 2
curl -s http://127.0.0.1:8888/api/health || {
  echo "Health check failed. Check homespace.log or pm2 logs homespace."
  exit 1
}

echo ""
echo "8. Checking Remote Tunnel Options..."
if command -v tailscale &> /dev/null; then
  echo "Setting up Tailscale Funnel on port 8443..."
  tailscale serve --https=8443 8888 || true
  tailscale funnel 8443 on || true
  echo "✓ Tailscale Funnel enabled on port 8443."
fi

if command -v cloudflared &> /dev/null; then
  echo "✓ cloudflared is installed. Cloudflare Tunnel is available."
fi

TS_IP=$(tailscale ip -4 2>/dev/null | head -n 1 || echo "<tailscale-ip>")
TS_DNS=$(tailscale status --self --json 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);console.log((j.Self?.DNSName||'').replace(/\.$/,''));}catch{}})" 2>/dev/null || true)

echo ""
echo "================================================="
echo "  SUCCESS! HomeSpace Server is running on port 8888"
echo "  Local Network:   http://$(hostname -I | awk '{print $1}'):8888"
echo "  Tailscale Mesh:  http://${TS_IP}:8888"
if [ -n "${TS_DNS}" ]; then
  echo "  Tailscale Funnel: https://${TS_DNS}:8443"
fi
echo "================================================="
