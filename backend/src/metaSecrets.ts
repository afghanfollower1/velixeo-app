import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export type EncryptedMetaSecret = {
  ciphertext: string;
  iv: string;
  tag: string;
};

function encryptionKey() {
  const raw = process.env.ADMIN_SECRET_ENCRYPTION_KEY?.trim();
  if (!raw) return null;
  let key: Buffer;
  if (/^[0-9a-f]{64}$/i.test(raw)) {
    key = Buffer.from(raw, 'hex');
  } else {
    try { key = Buffer.from(raw, 'base64'); } catch { return null; }
  }
  return key.length === 32 ? key : null;
}

export function metaSecretEncryptionConfigured() {
  return encryptionKey() !== null;
}

export function encryptMetaSecret(plaintext: string): EncryptedMetaSecret {
  const key = encryptionKey();
  if (!key) throw new Error('META_SECRET_ENCRYPTION_NOT_CONFIGURED');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return { ciphertext: encrypted.toString('base64'), iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64') };
}

export function decryptMetaSecret(source: { ciphertext?: string | null; iv?: string | null; tag?: string | null }) {
  if (!source.ciphertext || !source.iv || !source.tag) return null;
  const key = encryptionKey();
  if (!key) throw new Error('META_SECRET_ENCRYPTION_NOT_CONFIGURED');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(source.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(source.tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(source.ciphertext, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}
