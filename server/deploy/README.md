# HomeSpace Deployment on Xubuntu Laptop

This guide provides instructions to deploy and host the HomeSpace backend server on your Xubuntu laptop (running side-by-side with MyVibe without conflict).

## Network & Port Details
- **Assigned Port**: `8888` (MyVibe runs on `8787`)
- **Local IP**: `http://192.168.0.108:8888`
- **Tailscale IP**: `http://100.113.105.20:8888`
- **Data Directory**: `~/homespace-data/`

---

## Quick 1-Command Deployment

On the Xubuntu laptop terminal (or via SSH `ssh vishal@192.168.0.108`):

```bash
# 1. Download and run the automated deployment script:
curl -sSL https://raw.githubusercontent.com/VishalNakum1210/HomeSpace/main/server/deploy/deploy_laptop.sh | bash
```

---

## Manual Deployment Steps (Alternative)

If you prefer running commands manually:

```bash
# 1. Clone or pull repo
cd ~
git clone https://github.com/VishalNakum1210/HomeSpace.git
cd HomeSpace/server

# 2. Install dependencies
corepack pnpm install

# 3. Create .env
cat <<EOF > .env
HOST=0.0.0.0
PORT=8888
DATA_DIR=/home/vishal/homespace-data
NODE_ENV=production
DEFAULT_USER_QUOTA_BYTES=10737418240
EOF

# 4. Start with PM2
pm2 start src/index.js --name homespace
pm2 save

# 5. Verify Health Check
curl http://localhost:8888/api/health
```

Expected output:
```json
{"status":"ok","service":"homespace","version":"1.0.0","serverTime":"..."}
```

---

## Auto-Start on System Boot

Because PM2 is already configured on the laptop from the MyVibe project, running `pm2 save` automatically includes `homespace` in the system boot service alongside MyVibe!

To check logs anytime:
```bash
pm2 logs homespace
```
To restart:
```bash
pm2 restart homespace
```
