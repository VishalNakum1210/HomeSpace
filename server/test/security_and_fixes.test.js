import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

function buildMultipart(filename, fileBuffer, mimeType = 'image/jpeg', boundary = '----HomeSpaceTestBoundary') {
  const header = Buffer.from(
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
    `Content-Type: ${mimeType}\r\n\r\n`,
  );
  const footer = Buffer.from(`\r\n--${boundary}--\r\n`);
  return {
    payload: Buffer.concat([header, fileBuffer, footer]),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

test('Security & correctness regressions suite', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-sec-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
    DEFAULT_USER_QUOTA_BYTES: '1000',
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const reg1 = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'owner@homespace.local', password: 'password123', name: 'Owner' },
  });
  const reg2 = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'member@homespace.local', password: 'password123', name: 'Member' },
  });
  const reg3 = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'outsider@homespace.local', password: 'password123', name: 'Outsider' },
  });

  const owner = JSON.parse(reg1.payload);
  const member = JSON.parse(reg2.payload);
  const outsider = JSON.parse(reg3.payload);

  const sampleData = Buffer.from('0123456789abcdefghij'); // 20 bytes
  let mediaA;
  let mediaB;

  await t.test('Upload & /auth/me & /media/storage-breakdown report live usedBytes', async () => {
    const mp1 = buildMultipart('a.jpg', sampleData);
    const up1 = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: { authorization: `Bearer ${owner.token}`, 'content-type': mp1.contentType },
      payload: mp1.payload,
    });
    assert.equal(up1.statusCode, 201);
    mediaA = JSON.parse(up1.payload).media;

    const mp2 = buildMultipart('b.jpg', sampleData);
    const up2 = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: { authorization: `Bearer ${owner.token}`, 'content-type': mp2.contentType },
      payload: mp2.payload,
    });
    assert.equal(up2.statusCode, 201);
    mediaB = JSON.parse(up2.payload).media;

    const meRes = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${owner.token}` },
    });
    assert.equal(meRes.statusCode, 200);
    const me = JSON.parse(meRes.payload).user;
    assert.equal(me.storage.usedBytes, 40);
    assert.equal(me.storage.quotaBytes, 1000);
    assert.equal(me.storage.remainingBytes, 960);

    const bdRes = await app.inject({
      method: 'GET',
      url: '/api/media/storage-breakdown',
      headers: { authorization: `Bearer ${owner.token}` },
    });
    assert.equal(bdRes.statusCode, 200);
    const bd = JSON.parse(bdRes.payload);
    assert.equal(bd.totalUsedBytes, 40);
    assert.equal(bd.photosBytes, 40);
    assert.equal(bd.freeBytes, 960);
  });

  await t.test('Shared album memberships allow invited member media access and block uninvited user', async () => {
    const createAlbum = await app.inject({
      method: 'POST',
      url: '/api/albums',
      headers: { authorization: `Bearer ${owner.token}` },
      payload: {
        title: 'Private Family Trio',
        mediaIds: [mediaA.id, mediaB.id],
        isShared: true,
        memberships: [{ userId: member.user.id, role: 'contributor' }],
      },
    });
    assert.equal(createAlbum.statusCode, 201);
    const album = JSON.parse(createAlbum.payload).album;
    assert.equal(album.memberships.length, 1);
    assert.equal(album.memberships[0].userId, member.user.id);
    assert.equal(album.coverMediaId, mediaA.id);

    // Invited member can read album & stream media inside shared album
    const memAlbumRes = await app.inject({
      method: 'GET',
      url: `/api/albums/${album.id}?includeMedia=true`,
      headers: { authorization: `Bearer ${member.token}` },
    });
    assert.equal(memAlbumRes.statusCode, 200);
    const memAlbum = JSON.parse(memAlbumRes.payload).album;
    assert.equal(memAlbum.media.length, 2);

    const memFileRes = await app.inject({
      method: 'GET',
      url: `/api/media/${mediaA.id}/file`,
      headers: { authorization: `Bearer ${member.token}` },
    });
    assert.equal(memFileRes.statusCode, 200);
    assert.equal(memFileRes.headers['cache-control'], 'private, max-age=3600');

    // Uninvited outsider cannot view album or its media
    const outAlbumRes = await app.inject({
      method: 'GET',
      url: `/api/albums/${album.id}`,
      headers: { authorization: `Bearer ${outsider.token}` },
    });
    assert.equal(outAlbumRes.statusCode, 403);

    const outFileRes = await app.inject({
      method: 'GET',
      url: `/api/media/${mediaA.id}/file`,
      headers: { authorization: `Bearer ${outsider.token}` },
    });
    assert.equal(outFileRes.statusCode, 404);

    // Invited member still cannot trash owner's media
    const outTrash = await app.inject({
      method: 'POST',
      url: `/api/media/${mediaA.id}/trash`,
      headers: { authorization: `Bearer ${member.token}` },
    });
    assert.equal(outTrash.statusCode, 404);
  });

  await t.test('Range header clamps end, supports suffix bytes, and rejects invalid ranges', async () => {
    const clampRes = await app.inject({
      method: 'GET',
      url: `/api/media/${mediaA.id}/file`,
      headers: { authorization: `Bearer ${owner.token}`, range: 'bytes=15-999' },
    });
    assert.equal(clampRes.statusCode, 206);
    assert.equal(clampRes.headers['content-range'], 'bytes 15-19/20');
    assert.equal(clampRes.rawPayload.toString(), 'fghij');

    const suffixRes = await app.inject({
      method: 'GET',
      url: `/api/media/${mediaA.id}/file`,
      headers: { authorization: `Bearer ${owner.token}`, range: 'bytes=-4' },
    });
    assert.equal(suffixRes.statusCode, 206);
    assert.equal(suffixRes.headers['content-range'], 'bytes 16-19/20');
    assert.equal(suffixRes.rawPayload.toString(), 'ghij');

    const badRes = await app.inject({
      method: 'GET',
      url: `/api/media/${mediaA.id}/file`,
      headers: { authorization: `Bearer ${owner.token}`, range: 'bytes=-5-2' },
    });
    assert.equal(badRes.statusCode, 416);
  });

  await t.test('GET /media safely handles invalid kind and NaN limit/offset', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/media?limit=abc&offset=xyz&kind=invalid',
      headers: { authorization: `Bearer ${owner.token}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.limit, 100);
    assert.equal(body.offset, 0);
    assert.equal(body.total, 2);
  });

  await t.test('POST /trash/empty with ids only empties targeted items and updates album cover cleanly', async () => {
    // Trash both items
    await app.inject({
      method: 'POST',
      url: '/api/media/trash',
      headers: { authorization: `Bearer ${owner.token}` },
      payload: { ids: [mediaA.id, mediaB.id] },
    });

    // Empty ONLY mediaA.id
    const emptyPartial = await app.inject({
      method: 'POST',
      url: '/api/trash/empty',
      headers: { authorization: `Bearer ${owner.token}` },
      payload: { ids: [mediaA.id] },
    });
    assert.equal(emptyPartial.statusCode, 200);
    const partialBody = JSON.parse(emptyPartial.payload);
    assert.equal(partialBody.count, 1);

    // mediaB must STILL exist in trash!
    const trashCheck = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${owner.token}` },
    });
    const trashBody = JSON.parse(trashCheck.payload);
    assert.equal(trashBody.total, 1);
    assert.equal(trashBody.items[0].id, mediaB.id);

    // Album cover must have fallen back to mediaB cleanly without crashing
    const albRes = await app.inject({
      method: 'GET',
      url: '/api/albums',
      headers: { authorization: `Bearer ${owner.token}` },
    });
    const albums = JSON.parse(albRes.payload).albums;
    assert.equal(albums[0].coverMediaId, mediaB.id);
  });
});

test('REGISTRATION_OPEN=false blocks self-registration', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-closed-reg-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({ DATA_DIR: tmpDir, REGISTRATION_OPEN: 'false' });
  const app = await buildApp({ db, dataDir: tmpDir, config });
  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'blocked@homespace.local', password: 'password123', name: 'Blocked' },
  });
  assert.equal(res.statusCode, 403);
  assert.equal(JSON.parse(res.payload).error.code, 'REGISTRATION_DISABLED');
});
