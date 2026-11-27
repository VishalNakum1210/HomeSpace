import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { cleanupExpiredTempUploads } from '../src/routes/media.js';

test('Media Pipeline: upload, thumbnail, timeline, streaming, favorites, and trash', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-media-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
    DEFAULT_USER_QUOTA_BYTES: '100000', // 100 KB small quota to test limits
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  let token = '';
  let userId = '';
  let uploadedMediaId = '';

  // Setup: register user
  await t.test('Setup: register test user', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'media_test@homespace.local',
        password: 'password12345',
        name: 'Media Tester',
      },
    });
    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    token = body.token;
    userId = body.user.id;
  });

  // 1x1 24-bit JPEG buffer
  const sampleJpeg = Buffer.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
    0x00, 0x48, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
    0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
    0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20,
    0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27,
    0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
    0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f,
    0x00, 0xbf, 0x00, 0xff, 0xd9
  ]);

  function buildMultipart(filename, fileBuffer, mimeType = 'image/jpeg', boundary = '----WebKitFormBoundaryXYZ') {
    const header = Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: ${mimeType}\r\n\r\n`
    );
    const footer = Buffer.from(`\r\n--${boundary}--\r\n`);
    return {
      payload: Buffer.concat([header, fileBuffer, footer]),
      contentType: `multipart/form-data; boundary=${boundary}`,
    };
  }

  await t.test('POST /api/media/upload creates media and updates quota', async () => {
    const multipart = buildMultipart('IMG_20261121_120000.jpg', sampleJpeg);
    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload?takenAt=2026-11-21T12:00:00.000Z',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': multipart.contentType,
      },
      payload: multipart.payload,
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.media.id);
    assert.equal(body.media.filename, 'IMG_20261121_120000.jpg');
    assert.equal(body.media.kind, 'photo');
    assert.equal(body.media.size, sampleJpeg.length);
    assert.equal(body.media.isFavorite, false);

    uploadedMediaId = body.media.id;

    // Check user quota updated
    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), sampleJpeg.length);
  });

  await t.test('GET /api/media returns timeline with uploaded item', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.total, 1);
    assert.equal(body.items[0].id, uploadedMediaId);
    assert.equal(body.items[0].filename, 'IMG_20261121_120000.jpg');
  });

  await t.test('GET /api/media/:id returns single metadata', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.media.id, uploadedMediaId);
  });

  await t.test('GET /api/media/:id/thumb streams thumbnail', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/thumb`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    assert.ok(res.headers['content-type'].includes('image/'));
    assert.ok(res.rawPayload.length > 0);
  });

  await t.test('GET /api/media/:id/file streams full original and supports Range requests', async () => {
    // Full request
    const fullRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(fullRes.statusCode, 200);
    assert.equal(fullRes.rawPayload.length, sampleJpeg.length);
    assert.equal(fullRes.headers['accept-ranges'], 'bytes');

    // Partial Range request: first 10 bytes
    const rangeRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: {
        authorization: `Bearer ${token}`,
        range: 'bytes=0-9',
      },
    });

    assert.equal(rangeRes.statusCode, 206);
    assert.equal(rangeRes.rawPayload.length, 10);
    assert.equal(rangeRes.headers['content-range'], `bytes 0-9/${sampleJpeg.length}`);
    assert.deepEqual(rangeRes.rawPayload, sampleJpeg.subarray(0, 10));
  });

  await t.test('PATCH /api/media/:id toggles favorite', async () => {
    const favRes = await app.inject({
      method: 'PATCH',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
      payload: { isFavorite: true },
    });

    assert.equal(favRes.statusCode, 200);
    const body = JSON.parse(favRes.payload);
    assert.equal(body.media.isFavorite, true);

    // Filter query
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media?favorite=true',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    const listBody = JSON.parse(listRes.payload);
    assert.equal(listBody.total, 1);
  });

  await t.test('POST /api/media/:id/trash moves to trash and hides from timeline', async () => {
    const trashRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/trash`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(trashRes.statusCode, 200);

    // Standard timeline should now be empty
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(listRes.payload).total, 0);

    // Trash query should return 1
    const trashListRes = await app.inject({
      method: 'GET',
      url: '/api/media?trashed=true',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(trashListRes.payload).total, 1);
  });

  await t.test('POST /api/media/:id/restore restores from trash', async () => {
    const restoreRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/restore`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(restoreRes.statusCode, 200);

    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(listRes.payload).total, 1);
  });

  await t.test('DELETE /api/media/:id removes file and refunds quota', async () => {
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(delRes.statusCode, 200);

    // Database record deleted
    const checkDb = db.prepare('SELECT id FROM media WHERE id = ?').get(uploadedMediaId);
    assert.equal(checkDb, undefined);

    // Quota refunded back to 0
    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), 0);
  });

  await t.test('Upload rejects when file exceeds user quota (413 QUOTA_EXCEEDED)', async () => {
    // Quota was set to 100 KB (100,000 bytes)
    const giantPayload = Buffer.alloc(150000, 0x41);
    const multipart = buildMultipart('giant.bin', giantPayload);

    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': multipart.contentType,
      },
      payload: multipart.payload,
    });

    assert.equal(res.statusCode, 413);
    const body = JSON.parse(res.payload);
    assert.equal(body.error.code, 'QUOTA_EXCEEDED');
  });

  await t.test('Phase 6: Trash aliases and empty / purge lifecycle', async () => {
    // Upload a test photo
    const payload = Buffer.from('phase6-test-content');
    const mp = buildMultipart('trash-photo.jpg', payload);
    const upRes = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': mp.contentType,
      },
      payload: mp.payload,
    });
    assert.equal(upRes.statusCode, 201);
    const item = JSON.parse(upRes.payload).media;

    // Move to trash
    const trashRes = await app.inject({
      method: 'POST',
      url: '/api/media/trash',
      headers: { authorization: `Bearer ${token}` },
      payload: { ids: [item.id] },
    });
    assert.equal(trashRes.statusCode, 200);

    // GET /api/trash
    const listTrashRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(listTrashRes.statusCode, 200);
    const trashData = JSON.parse(listTrashRes.payload);
    assert.equal(trashData.total, 1);
    assert.equal(trashData.items[0].id, item.id);
    assert.equal(trashData.items[0].isTrashed, true);
    assert.ok(trashData.items[0].trashedAt);

    // Empty trash
    const emptyRes = await app.inject({
      method: 'POST',
      url: '/api/trash/empty',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(emptyRes.statusCode, 200);
    const emptyBody = JSON.parse(emptyRes.payload);
    assert.equal(emptyBody.count, 1);

    // Verify trash is now empty and user quota is 0
    const checkTrashRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(JSON.parse(checkTrashRes.payload).total, 0);

    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), 0);
  });

  await t.test('Delete and trash by filenames (matching local device uploads)', async () => {
    // Upload a photo
    const payload = Buffer.from('filename-delete-test');
    const mp = buildMultipart('my_camera_shot.jpg', payload);
    const upRes = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': mp.contentType,
      },
      payload: mp.payload,
    });
    assert.equal(upRes.statusCode, 201);

    // Trash by filename (e.g. client only knew local ID but passed filename)
    const trashRes = await app.inject({
      method: 'POST',
      url: '/api/media/trash',
      headers: { authorization: `Bearer ${token}` },
      payload: { ids: ['non_existent_local_id'], filenames: ['my_camera_shot.jpg'] },
    });
    assert.equal(trashRes.statusCode, 200);
    assert.equal(JSON.parse(trashRes.payload).count, 1);

    // Verify it is in trash
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(JSON.parse(listRes.payload).total, 1);

    // Delete permanently by filename
    const delRes = await app.inject({
      method: 'POST',
      url: '/api/media/delete',
      headers: { authorization: `Bearer ${token}` },
      payload: { ids: ['non_existent_local_id'], filenames: ['my_camera_shot.jpg'] },
    });
    assert.equal(delRes.statusCode, 200);
    assert.equal(JSON.parse(delRes.payload).count, 1);

    // Verify completely gone
    const checkRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(JSON.parse(checkRes.payload).total, 0);

    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), 0);
  });

  await t.test('Chunked upload: init rejects over-quota upfront, supports resume, complete, cancel, and TTL cleanup', async () => {
    // 1. Pre-check rejects file exceeding available quota (100,000 bytes) before uploading chunks
    const tooLargeInit = await app.inject({
      method: 'POST',
      url: '/api/media/upload/init',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        filename: 'too_big.mp4',
        mimeType: 'video/mp4',
        totalBytes: 200000,
      },
    });
    assert.equal(tooLargeInit.statusCode, 413);
    assert.equal(JSON.parse(tooLargeInit.payload).error.code, 'QUOTA_EXCEEDED');

    // 2. Initialize a valid chunked upload (120 bytes in 2 chunks)
    const videoContent = Buffer.concat([
      Buffer.alloc(60, 0x41),
      Buffer.alloc(60, 0x42),
    ]);
    const initRes = await app.inject({
      method: 'POST',
      url: '/api/media/upload/init',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        filename: 'family_clip.mp4',
        mimeType: 'video/mp4',
        totalBytes: videoContent.length,
        takenAt: '2026-11-27T10:00:00.000Z',
      },
    });
    assert.equal(initRes.statusCode, 201);
    const { uploadId } = JSON.parse(initRes.payload);
    assert.ok(uploadId);

    // 3. Upload first chunk (0..60)
    const chunk1Res = await app.inject({
      method: 'PUT',
      url: `/api/media/upload/${uploadId}/chunk?offset=0`,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/octet-stream',
      },
      payload: videoContent.subarray(0, 60),
    });
    assert.equal(chunk1Res.statusCode, 200);
    assert.equal(JSON.parse(chunk1Res.payload).bytesReceived, 60);

    // 4. Query status for resume offset
    const statusRes = await app.inject({
      method: 'GET',
      url: `/api/media/upload/${uploadId}`,
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(statusRes.statusCode, 200);
    assert.equal(JSON.parse(statusRes.payload).bytesReceived, 60);

    // 5. Wrong offset returns 409 OFFSET_MISMATCH with current bytesReceived
    const badOffsetRes = await app.inject({
      method: 'PUT',
      url: `/api/media/upload/${uploadId}/chunk?offset=0`,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/octet-stream',
      },
      payload: videoContent.subarray(0, 60),
    });
    assert.equal(badOffsetRes.statusCode, 409);
    assert.equal(JSON.parse(badOffsetRes.payload).error.bytesReceived, 60);

    // 6. Upload second chunk (60..120) and complete
    const chunk2Res = await app.inject({
      method: 'PUT',
      url: `/api/media/upload/${uploadId}/chunk?offset=60`,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/octet-stream',
      },
      payload: videoContent.subarray(60, 120),
    });
    assert.equal(chunk2Res.statusCode, 200);
    assert.equal(JSON.parse(chunk2Res.payload).bytesReceived, 120);

    const completeRes = await app.inject({
      method: 'POST',
      url: `/api/media/upload/${uploadId}/complete`,
      headers: { authorization: `Bearer ${token}` },
      payload: {},
    });
    assert.equal(completeRes.statusCode, 201);
    const completedMedia = JSON.parse(completeRes.payload).media;
    assert.equal(completedMedia.filename, 'family_clip.mp4');
    assert.equal(completedMedia.kind, 'video');
    assert.equal(completedMedia.size, 120);

    // Temp directory cleaned up, file streamable with full content
    assert.equal(fs.existsSync(path.join(tmpDir, 'tmp_uploads', uploadId)), false);
    const streamRes = await app.inject({
      method: 'GET',
      url: `/api/media/${completedMedia.id}/file`,
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(streamRes.statusCode, 200);
    assert.deepEqual(streamRes.rawPayload, videoContent);

    // Clean up completed media to reset quota to 0
    await app.inject({
      method: 'DELETE',
      url: `/api/media/${completedMedia.id}`,
      headers: { authorization: `Bearer ${token}` },
    });

    // 7. Cancel deletes temp chunks immediately
    const cancelInit = await app.inject({
      method: 'POST',
      url: '/api/media/upload/init',
      headers: { authorization: `Bearer ${token}` },
      payload: { filename: 'canceled.mp4', mimeType: 'video/mp4', totalBytes: 100 },
    });
    const cancelId = JSON.parse(cancelInit.payload).uploadId;
    await app.inject({
      method: 'PUT',
      url: `/api/media/upload/${cancelId}/chunk?offset=0`,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/octet-stream',
      },
      payload: Buffer.alloc(50, 0x43),
    });
    assert.equal(fs.existsSync(path.join(tmpDir, 'tmp_uploads', cancelId)), true);

    const cancelRes = await app.inject({
      method: 'DELETE',
      url: `/api/media/upload/${cancelId}`,
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(cancelRes.statusCode, 200);
    assert.equal(fs.existsSync(path.join(tmpDir, 'tmp_uploads', cancelId)), false);

    // 8. Abandoned upload session cleanup removes expired temp directories
    const expiredInit = await app.inject({
      method: 'POST',
      url: '/api/media/upload/init',
      headers: { authorization: `Bearer ${token}` },
      payload: { filename: 'abandoned.mp4', mimeType: 'video/mp4', totalBytes: 100 },
    });
    const expiredId = JSON.parse(expiredInit.payload).uploadId;
    const expiredMetaPath = path.join(tmpDir, 'tmp_uploads', expiredId, 'meta.json');
    const expiredMeta = JSON.parse(fs.readFileSync(expiredMetaPath, 'utf8'));
    expiredMeta.updatedAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
    fs.writeFileSync(expiredMetaPath, JSON.stringify(expiredMeta));

    const cleanedCount = cleanupExpiredTempUploads(path.join(tmpDir, 'tmp_uploads'));
    assert.equal(cleanedCount, 1);
    assert.equal(fs.existsSync(path.join(tmpDir, 'tmp_uploads', expiredId)), false);
  });
});
