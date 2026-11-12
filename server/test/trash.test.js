import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import sharp from 'sharp';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

async function createMultipartPayload(fieldName, buffer, filename, mimeType) {
  const form = new FormData();
  form.append(fieldName, new Blob([buffer], { type: mimeType }), filename);
  const response = new Response(form);
  const payload = Buffer.from(await response.arrayBuffer());
  const contentType = response.headers.get('content-type');
  return { payload, contentType };
}

test('Trash API: Empty Trash & Quota Restoration', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-trash-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({ DATA_DIR: tmpDir });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const aRes = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'charlie@test.com', password: 'password123', name: 'Charlie' },
  });
  const charlie = JSON.parse(aRes.payload);
  const token = charlie.token;

  // Upload 2 photos
  const imgBuf = await sharp({
    create: { width: 20, height: 20, channels: 4, background: { r: 10, g: 10, b: 10, alpha: 1 } },
  }).png().toBuffer();

  const { payload, contentType } = await createMultipartPayload('file', imgBuf, 'p1.png', 'image/png');
  const u1 = await app.inject({
    method: 'POST',
    url: '/api/media/upload',
    headers: { authorization: `Bearer ${token}`, 'content-type': contentType },
    payload,
  });
  const photo1 = JSON.parse(u1.payload).id;

  const u2 = await app.inject({
    method: 'POST',
    url: '/api/media/upload',
    headers: { authorization: `Bearer ${token}`, 'content-type': contentType },
    payload,
  });
  const photo2 = JSON.parse(u2.payload).id;

  // Check storage used
  const meBefore = await app.inject({
    method: 'GET',
    url: '/api/auth/me',
    headers: { authorization: `Bearer ${token}` },
  });
  const usedBefore = JSON.parse(meBefore.payload).user.storage.usedBytes;
  assert.ok(usedBefore > 0);

  // Trash both photos
  await app.inject({ method: 'POST', url: `/api/media/${photo1}/trash`, headers: { authorization: `Bearer ${token}` } });
  await app.inject({ method: 'POST', url: `/api/media/${photo2}/trash`, headers: { authorization: `Bearer ${token}` } });

  // List trash
  const trashRes = await app.inject({
    method: 'GET',
    url: '/api/trash',
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(trashRes.statusCode, 200);
  assert.equal(JSON.parse(trashRes.payload).items.length, 2);

  // Empty trash permanently
  const emptyRes = await app.inject({
    method: 'POST',
    url: '/api/trash/empty',
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(emptyRes.statusCode, 200);
  const emptyBody = JSON.parse(emptyRes.payload);
  assert.equal(emptyBody.deletedCount, 2);
  assert.equal(emptyBody.storageUsedBytes, 0);

  // Verify disk files gone
  assert.equal(fs.existsSync(path.join(tmpDir, 'users', charlie.user.id, 'originals', `${photo1}.png`)), false);
  assert.equal(fs.existsSync(path.join(tmpDir, 'users', charlie.user.id, 'originals', `${photo2}.png`)), false);

  // Verify trash is now empty
  const emptyCheck = await app.inject({
    method: 'GET',
    url: '/api/trash',
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(JSON.parse(emptyCheck.payload).items.length, 0);
});
