import test from 'node:test';
import assert from 'node:assert/strict';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

test('GET /api/health returns 200 OK and valid status', async () => {
  const db = initDatabase(':memory:');
  const config = loadConfig({ DATA_DIR: './test-data' });
  const app = await buildApp({ db, dataDir: './test-data', config });

  const response = await app.inject({
    method: 'GET',
    url: '/api/health',
  });

  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.payload);
  assert.equal(body.status, 'ok');
  assert.equal(body.service, 'homespace');
  assert.equal(body.version, '1.0.0');
  assert.ok(body.serverTime);

  await app.close();
});
