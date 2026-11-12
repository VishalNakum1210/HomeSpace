import { deleteMediaFiles, updateStorageUsage } from '../storage.js';

const EXTENSION_MAP = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/avif': 'avif',
};

export async function trashRoutes(fastify, options) {
  const { db, dataDir } = options;

  fastify.addHook('preHandler', fastify.authenticate);

  // 1. List trash items
  fastify.get('/trash', async (req, reply) => {
    const rows = db.prepare(`
      SELECT * FROM media 
      WHERE user_id = ? AND is_trashed = 1 
      ORDER BY trashed_at DESC
    `).all(req.user.id);

    return {
      items: rows.map(r => ({
        id: r.id,
        userId: r.user_id,
        fileName: r.file_name,
        mimeType: r.mime_type,
        byteSize: Number(r.byte_size),
        width: r.width,
        height: r.height,
        takenAt: r.taken_at,
        createdAt: r.created_at,
        isFavorite: Boolean(r.is_favorite),
        isTrashed: true,
        trashedAt: r.trashed_at,
      })),
    };
  });

  // 2. Empty trash permanently
  fastify.post('/trash/empty', async (req, reply) => {
    const rows = db.prepare(`
      SELECT id, mime_type, byte_size 
      FROM media 
      WHERE user_id = ? AND is_trashed = 1
    `).all(req.user.id);

    let deletedCount = 0;
    let totalBytesRecovered = 0;

    for (const item of rows) {
      const ext = EXTENSION_MAP[item.mime_type] || 'jpg';
      deleteMediaFiles(dataDir, req.user.id, item.id, ext);
      db.prepare('DELETE FROM media WHERE id = ?').run(item.id);
      totalBytesRecovered += Number(item.byte_size);
      deletedCount++;
    }

    let updatedStorage = { usedBytes: 0, quotaBytes: 0 };
    if (totalBytesRecovered > 0) {
      updatedStorage = updateStorageUsage(db, req.user.id, -totalBytesRecovered);
    } else {
      const check = db.prepare('SELECT storage_used_bytes, storage_quota_bytes FROM users WHERE id = ?').get(req.user.id);
      updatedStorage = {
        usedBytes: Number(check.storage_used_bytes),
        quotaBytes: Number(check.storage_quota_bytes),
      };
    }

    return {
      emptied: true,
      deletedCount,
      recoveredBytes: totalBytesRecovered,
      storageUsedBytes: updatedStorage.usedBytes,
    };
  });
}
