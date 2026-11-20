#!/usr/bin/env node
/**
 * ============================================================================
 * HomeSpace CLI Tool — Defensive & Secure Command Line Interface
 * ============================================================================
 * Safeguards Enforced:
 * 1. Strict File Validation: Client-side magic byte pre-flight verification.
 * 2. Safe File Path Handling: Sanitizes all filenames and paths, prevents path traversal.
 * 3. Access Control & Session Safety: Secure token storage (chmod 0600), Bearer auth headers.
 * 4. Safe Command Execution: Uses parameterized execFile (NO raw shell strings/interpolation).
 * 5. Strict Permissions: Config file stored in ~/.homespace/config.json with 0o600/0o700.
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { validateMagicBytes, ALLOWED_MIME_TYPES } from './storage.js';

const execFileAsync = promisify(execFile);

// Config directory and file paths
const CONFIG_DIR = path.join(os.homedir(), '.homespace');
const CONFIG_PATH = path.join(CONFIG_DIR, 'config.json');

/**
 * Ensure config directory exists with 0o700 (owner-only access)
 */
function ensureConfigDir() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  }
}

/**
 * Load user session config from disk with defensive parsing
 */
function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
      return JSON.parse(raw);
    }
  } catch (_) {
    // If corrupted or unreadable, treat as not logged in
  }
  return null;
}

/**
 * Save user session config with strict 0o600 (owner read/write only) permissions
 */
function saveConfig(config) {
  ensureConfigDir();
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), { mode: 0o600 });
  // Explicitly ensure permissions on existing files
  try {
    fs.chmodSync(CONFIG_PATH, 0o600);
  } catch (_) {}
}

/**
 * Sanitize filename to prevent directory traversal or shell character injection
 */
function sanitizeFileName(inputPath) {
  const baseName = path.basename(inputPath);
  // Strip null bytes and non-printable characters
  const clean = baseName.replace(/[\x00-\x1F\x7F<>:"/\\|?*]/g, '_');
  if (!clean || clean === '.' || clean === '..') {
    throw new Error('Invalid file name: Potentially malicious path traversal detected.');
  }
  return clean;
}

/**
 * CLI Command: Login and store session token securely
 */
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
  console.log(`Session token saved securely to ${CONFIG_PATH} (mode 0600).`);
}

/**
 * CLI Command: Upload photo/video with strict magic-byte validation and safe path handling
 */
async function handleUpload(filePath) {
  const config = loadConfig();
  if (!config || !config.token || !config.serverUrl) {
    console.error('Error: Not authenticated. Run "homespace login" first.');
    process.exit(1);
  }

  // 1. Resolve and verify file existence
  const resolvedPath = path.resolve(filePath);
  if (!fs.existsSync(resolvedPath)) {
    console.error(`Error: File not found at path: ${resolvedPath}`);
    process.exit(1);
  }

  // 2. Sanitize filename to prevent directory traversal attacks
  const safeName = sanitizeFileName(resolvedPath);

  // 3. Pre-flight binary magic byte inspection (No spoofed extensions permitted)
  const magicMime = validateMagicBytes(resolvedPath);
  if (!magicMime || !ALLOWED_MIME_TYPES.has(magicMime)) {
    console.error(`Error: Security check rejected file. Unrecognized or unsupported binary format.`);
    console.error(`Allowed formats: JPEG, PNG, WebP, GIF, HEIC, AVIF, MP4, MOV, WebM, MKV`);
    process.exit(1);
  }

  const stat = fs.statSync(resolvedPath);
  console.log(`Uploading ${safeName} (${(stat.size / (1024 * 1024)).toFixed(2)} MB, ${magicMime})...`);

  // Build safe multipart form payload
  const fileBytes = fs.readFileSync(resolvedPath);
  const boundary = '----HomeSpaceCliFormBoundary' + Math.random().toString(36).substring(2);
  const postDataHeader = Buffer.from(
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${safeName}"\r\n` +
    `Content-Type: ${magicMime}\r\n\r\n`
  );
  const postDataFooter = Buffer.from(`\r\n--${boundary}--\r\n`);
  const fullBody = Buffer.concat([postDataHeader, fileBytes, postDataFooter]);

  const target = `${config.serverUrl}/api/media/upload`;
  const res = await fetch(target, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${config.token}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Content-Length': String(fullBody.length),
    },
    body: fullBody,
  });

  if (!res.ok) {
    const errorBody = await res.json().catch(() => ({}));
    console.error(`Upload failed [${res.status}]:`, errorBody.error?.message || res.statusText);
    process.exit(1);
  }

  const result = await res.json();
  console.log(`Upload successful!`);
  console.log(`  Media ID: ${result.id}`);
  console.log(`  File:     ${result.fileName}`);
  console.log(`  Size:     ${(result.byteSize / (1024 * 1024)).toFixed(2)} MB`);
}

/**
 * CLI Command: List media files with session token verification
 */
async function handleList() {
  const config = loadConfig();
  if (!config || !config.token || !config.serverUrl) {
    console.error('Error: Not authenticated. Run "homespace login" first.');
    process.exit(1);
  }

  const target = `${config.serverUrl}/api/media?limit=25`;
  const res = await fetch(target, {
    method: 'GET',
    headers: { 'Authorization': `Bearer ${config.token}` },
  });

  if (!res.ok) {
    console.error(`List failed [${res.status}]:`, res.statusText);
    process.exit(1);
  }

  const data = await res.json();
  console.log(`Recent Media (${data.items?.length || 0} items):`);
  for (const item of (data.items || [])) {
    const mb = (item.byteSize / (1024 * 1024)).toFixed(2);
    console.log(`  • [${item.id}] ${item.fileName} (${mb} MB, ${item.mimeType})`);
  }
}

/**
 * CLI Command: Safe media transcoding / extraction using parameterized execFile
 * Parameterized execution prevents OS command injection vulnerabilities.
 */
async function handleExtractThumbnail(videoPath, outputPath) {
  const safeIn = path.resolve(videoPath);
  const safeOut = path.resolve(outputPath);

  if (!fs.existsSync(safeIn)) {
    console.error(`Error: Input video not found: ${safeIn}`);
    process.exit(1);
  }

  // Safe Parameterized execution: execFile takes arguments array (NO shell interpolation)
  try {
    console.log(`Extracting thumbnail safely via FFmpeg...`);
    await execFileAsync('ffmpeg', [
      '-ss', '00:00:01',
      '-i', safeIn,
      '-vframes', '1',
      '-vf', 'scale=400:400:force_original_aspect_ratio=decrease',
      '-q:v', '2',
      '-y',
      safeOut,
    ]);

    // Restrict output file permissions to owner-only
    try { fs.chmodSync(safeOut, 0o600); } catch (_) {}
    console.log(`Thumbnail created safely at: ${safeOut}`);
  } catch (err) {
    console.error(`Command execution failed:`, err.message);
    process.exit(1);
  }
}

// Main CLI router
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case 'login':
      await handleLogin(args[1], args[2], args[3]);
      break;
    case 'upload':
      await handleUpload(args[1]);
      break;
    case 'list':
      await handleList();
      break;
    case 'extract-thumb':
      await handleExtractThumbnail(args[1], args[2]);
      break;
    default:
      console.log(`HomeSpace CLI — Secure Family Media Client`);
      console.log(`Usage:`);
      console.log(`  homespace login <serverUrl> <email> <password>`);
      console.log(`  homespace upload <path/to/media>`);
      console.log(`  homespace list`);
      console.log(`  homespace extract-thumb <videoPath> <outputPath>`);
      break;
  }
}

main().catch((err) => {
  console.error('Fatal CLI Error:', err.message);
  process.exit(1);
});
