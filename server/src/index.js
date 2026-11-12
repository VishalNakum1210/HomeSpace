import path from 'node:path';
import { loadConfig } from './config.js';
import { initDatabase } from './db.js';
import { buildApp } from './app.js';

async function start() {
  const config = loadConfig();
  const dbPath = path.join(config.dataDir, 'homespace.sqlite');
  
  console.log(`[HomeSpace Server] Initializing SQLite database at: ${dbPath}`);
  const db = initDatabase(dbPath);

  const app = await buildApp({
    db,
    dataDir: config.dataDir,
    config,
  });

  try {
    const address = await app.listen({
      port: config.port,
      host: config.host,
    });
    console.log(`[HomeSpace Server] Server is running and listening at ${address}`);
    console.log(`[HomeSpace Server] Health check available at: ${address}/api/health`);
  } catch (err) {
    console.error('[HomeSpace Server] Failed to start server:', err);
    process.exit(1);
  }
}

start();
