import crypto from 'node:crypto';

export function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  if (!password || typeof password !== 'string') {
    throw new Error('Password must be a non-empty string');
  }
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return { hash, salt };
}

export function verifyPassword(password, salt, expectedHash) {
  if (!password || !salt || !expectedHash) return false;
  const computedHash = crypto.scryptSync(password, salt, 64).toString('hex');
  
  const bufA = Buffer.from(computedHash, 'hex');
  const bufB = Buffer.from(expectedHash, 'hex');

  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

export function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}

export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function createSession(db, userId, expiryDays = 30) {
  const token = generateToken();
  const tokenHash = hashToken(token);
  const sessionId = 'sess_' + crypto.randomBytes(12).toString('hex');
  
  const now = new Date();
  const expiresAt = new Date(now.getTime() + expiryDays * 24 * 60 * 60 * 1000);

  const stmt = db.prepare(`
    INSERT INTO sessions (id, user_id, token_hash, created_at, expires_at, last_seen_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `);

  stmt.run(
    sessionId,
    userId,
    tokenHash,
    now.toISOString(),
    expiresAt.toISOString(),
    now.toISOString(),
  );

  return {
    token,
    expiresAt: expiresAt.toISOString(),
  };
}

export function authenticate(db) {
  return async function (req, reply) {
    let token = null;
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7).trim();
    } else if (req.query && req.query.token) {
      token = String(req.query.token).trim();
    }

    if (!token) {
      return reply.code(401).send({
        error: {
          code: 'UNAUTHORIZED',
          message: 'Missing or malformed Authorization header or token query parameter',
        },
      });
    }

    const tokenHash = hashToken(token);
    const nowIso = new Date().toISOString();

    const stmt = db.prepare(`
      SELECT 
        s.id AS session_id,
        s.expires_at,
        u.id,
        u.email,
        u.name,
        u.avatar_tone,
        u.storage_quota_bytes,
        u.storage_used_bytes,
        u.created_at
      FROM sessions s
      JOIN users u ON s.user_id = u.id
      WHERE s.token_hash = ? AND s.expires_at > ?
    `);

    const user = stmt.get(tokenHash, nowIso);

    if (!user) {
      return reply.code(401).send({
        error: {
          code: 'UNAUTHORIZED',
          message: 'Invalid or expired session token',
        },
      });
    }

    // Touch last_seen_at
    db.prepare('UPDATE sessions SET last_seen_at = ? WHERE id = ?').run(nowIso, user.session_id);

    req.user = {
      id: user.id,
      email: user.email,
      name: user.name,
      avatarTone: user.avatar_tone,
      storageQuotaBytes: Number(user.storage_quota_bytes),
      storageUsedBytes: Number(user.storage_used_bytes),
      createdAt: user.created_at,
    };
    req.sessionId = user.session_id;
  };
}
