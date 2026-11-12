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

test('Albums & Member Sharing API', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-albums-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({ DATA_DIR: tmpDir });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  // User Alice (Album Owner)
  const aRes = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'alice@alb.com', password: 'password123', name: 'Alice' },
  });
  const aliceToken = JSON.parse(aRes.payload).token;

  // User Bob (Invited Member)
  const bRes = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'bob@alb.com', password: 'password123', name: 'Bob' },
  });
  const bob = JSON.parse(bRes.payload);
  const bobToken = bob.token;

  // Alice uploads a photo
  const imgBuf = await sharp({
    create: { width: 30, height: 30, channels: 4, background: { r: 0, g: 255, b: 0, alpha: 1 } },
  }).png().toBuffer();
  const { payload, contentType } = await createMultipartPayload('file', imgBuf, 'green.png', 'image/png');
  const uploadRes = await app.inject({
    method: 'POST',
    url: '/api/media/upload',
    headers: { authorization: `Bearer ${aliceToken}`, 'content-type': contentType },
    payload,
  });
  const photoId = JSON.parse(uploadRes.payload).id;

  let albumId = '';

  await t.test('POST /api/albums creates new album with photos', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/albums',
      headers: { authorization: `Bearer ${aliceToken}` },
      payload: {
        title: 'Summer Vacation',
        description: 'Trip to the coast',
        coverMediaId: photoId,
        mediaIds: [photoId],
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.id);
    assert.equal(body.title, 'Summer Vacation');
    assert.equal(body.userRole, 'owner');
    albumId = body.id;
  });

  await t.test('GET /api/albums lists albums for Alice', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/albums',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.albums.length, 1);
    assert.equal(body.albums[0].id, albumId);
    assert.equal(body.albums[0].mediaCount, 1);
  });

  await t.test('Shared photo access: Bob cannot access photo until invited to album', async () => {
    // Before invite
    const pre = await app.inject({
      method: 'GET',
      url: `/api/media/${photoId}`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(pre.statusCode, 404);

    // Invite Bob to the album as viewer
    const inviteRes = await app.inject({
      method: 'POST',
      url: `/api/albums/${albumId}/members`,
      headers: { authorization: `Bearer ${aliceToken}` },
      payload: { email: 'bob@alb.com', role: 'viewer' },
    });
    assert.equal(inviteRes.statusCode, 200);

    // After invite: Bob CAN now access Alice's photo through the shared album!
    const post = await app.inject({
      method: 'GET',
      url: `/api/media/${photoId}`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(post.statusCode, 200);
    assert.equal(JSON.parse(post.payload).id, photoId);
  });

  await t.test('GET /api/albums lists shared album for Bob', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/albums',
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.albums.length, 1);
    assert.equal(body.albums[0].id, albumId);
    assert.equal(body.albums[0].userRole, 'viewer');
  });

  await t.test('Role permissions: Viewer cannot add media, but Contributor can', async () => {
    // Bob as viewer tries to add media -> forbidden
    const fail = await app.inject({
      method: 'POST',
      url: `/api/albums/${albumId}/media`,
      headers: { authorization: `Bearer ${bobToken}` },
      payload: { mediaIds: ['some-id'] },
    });
    assert.equal(fail.statusCode, 403);

    // Alice promotes Bob to contributor
    const promo = await app.inject({
      method: 'PATCH',
      url: `/api/albums/${albumId}/members/${bob.user.id}`,
      headers: { authorization: `Bearer ${aliceToken}` },
      payload: { role: 'contributor' },
    });
    assert.equal(promo.statusCode, 200);

    // Bob as contributor can now edit album title
    const edit = await app.inject({
      method: 'PATCH',
      url: `/api/albums/${albumId}`,
      headers: { authorization: `Bearer ${bobToken}` },
      payload: { title: 'Summer Vacation (Updated by Bob)' },
    });
    assert.equal(edit.statusCode, 200);
    assert.equal(JSON.parse(edit.payload).title, 'Summer Vacation (Updated by Bob)');
  });

  await t.test('DELETE /api/albums/:id deletes album but keeps photos in user library', async () => {
    // Bob cannot delete
    const failDel = await app.inject({
      method: 'DELETE',
      url: `/api/albums/${albumId}`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(failDel.statusCode, 403);

    // Alice deletes album
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/albums/${albumId}`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(del.statusCode, 200);

    // Alice still has the photo in her library!
    const photoCheck = await app.inject({
      method: 'GET',
      url: `/api/media/${photoId}`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(photoCheck.statusCode, 200);
  });
});
