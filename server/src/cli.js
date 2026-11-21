#!/usr/bin/env node
/**
 * HomeSpace CLI Tool — Authentication & Account Management
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const CONFIG_DIR = path.join(os.homedir(), '.homespace');
const CONFIG_PATH = path.join(CONFIG_DIR, 'config.json');

function ensureConfigDir() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  }
}

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
      return JSON.parse(raw);
    }
  } catch (_) {}
  return null;
}

function saveConfig(config) {
  ensureConfigDir();
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), { mode: 0o600 });
  try {
    fs.chmodSync(CONFIG_PATH, 0o600);
  } catch (_) {}
}

async function handleRegister(serverUrl, email, password, name) {
  if (!serverUrl || !email || !password || !name) {
    console.error('Usage: homespace register <serverUrl> <email> <password> <name>');
    process.exit(1);
  }

  const normalizedUrl = serverUrl.replace(/\/+$/, '');
  const target = `${normalizedUrl}/api/auth/register`;

  console.log(`Registering account at ${normalizedUrl}...`);
  const res = await fetch(target, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim(), password, name: name.trim() }),
  });

  if (!res.ok) {
    const errorBody = await res.json().catch(() => ({}));
    console.error(`Registration failed [${res.status}]:`, errorBody.error?.message || res.statusText);
    process.exit(1);
  }

  const data = await res.json();
  saveConfig({
    serverUrl: normalizedUrl,
    token: data.token,
    user: data.user,
    expiresAt: data.expiresAt,
  });

  console.log(`Successfully registered as ${data.user.name} (${data.user.email}).`);
  console.log(`Session token saved securely to ${CONFIG_PATH}.`);
}

async function handleLogin(serverUrl, email, password) {
  if (!serverUrl || !email || !password) {
    console.error('Usage: homespace login <serverUrl> <email> <password>');
    process.exit(1);
  }

  const normalizedUrl = serverUrl.replace(/\/+$/, '');
  const target = `${normalizedUrl}/api/auth/login`;

  console.log(`Authenticating with HomeSpace server at ${normalizedUrl}...`);
  const res = await fetch(target, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim(), password }),
  });

  if (!res.ok) {
    const errorBody = await res.json().catch(() => ({}));
    console.error(`Login failed [${res.status}]:`, errorBody.error?.message || res.statusText);
    process.exit(1);
  }

  const data = await res.json();
  saveConfig({
    serverUrl: normalizedUrl,
    token: data.token,
    user: data.user,
    expiresAt: data.expiresAt,
  });

  console.log(`Successfully authenticated as ${data.user.name} (${data.user.email}).`);
  console.log(`Session token saved securely to ${CONFIG_PATH}.`);
}

async function handleWhoami() {
  const config = loadConfig();
  if (!config || !config.token || !config.serverUrl) {
    console.error('Error: Not authenticated. Run "homespace login" or "homespace register" first.');
    process.exit(1);
  }

  const target = `${config.serverUrl}/api/auth/me`;
  const res = await fetch(target, {
    method: 'GET',
    headers: { 'Authorization': `Bearer ${config.token}` },
  });

  if (!res.ok) {
    console.error(`Whoami failed [${res.status}]:`, res.statusText);
    process.exit(1);
  }

  const data = await res.json();
  console.log(`Logged in User:`);
  console.log(`  Name:  ${data.user?.name}`);
  console.log(`  Email: ${data.user?.email}`);
  console.log(`  Tone:  ${data.user?.avatar_tone || data.user?.avatarTone}`);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case 'register':
      await handleRegister(args[1], args[2], args[3], args[4]);
      break;
    case 'login':
      await handleLogin(args[1], args[2], args[3]);
      break;
    case 'whoami':
      await handleWhoami();
      break;
    default:
      console.log(`HomeSpace CLI — Authentication & Account Client`);
      console.log(`Usage:`);
      console.log(`  homespace register <serverUrl> <email> <password> <name>`);
      console.log(`  homespace login <serverUrl> <email> <password>`);
      console.log(`  homespace whoami`);
      break;
  }
}

main().catch((err) => {
  console.error('Fatal CLI Error:', err.message);
  process.exit(1);
});
