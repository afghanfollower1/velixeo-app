import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export type EncryptedProviderSecret = {
  secretCiphertext: string;
  secretIv: string;
  secretTag: string;
};

type SecretSource = {
  secretCiphertext: string | null;
  secretIv: string | null;
  secretTag: string | null;
};

function encryptionKey() {
  const raw = process.env.ADMIN_SECRET_ENCRYPTION_KEY?.trim();
  if (!raw) return null;

  let key: Buffer;
  if (/^[0-9a-f]{64}$/i.test(raw)) {
    key = Buffer.from(raw, 'hex');
  } else {
    try {
      key = Buffer.from(raw, 'base64');
    } catch {
      return null;
    }
  }
  return key.length === 32 ? key : null;
}

export function providerSecretEncryptionConfigured() {
  return encryptionKey() !== null;
}

export function encryptProviderSecret(plaintext: string): EncryptedProviderSecret {
  const key = encryptionKey();
  if (!key) throw new Error('PROVIDER_SECRET_ENCRYPTION_NOT_CONFIGURED');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  return {
    secretCiphertext: ciphertext.toString('base64'),
    secretIv: iv.toString('base64'),
    secretTag: cipher.getAuthTag().toString('base64'),
  };
}

export function decryptProviderSecret(source: SecretSource) {
  if (!source.secretCiphertext || !source.secretIv || !source.secretTag) return null;
  const key = encryptionKey();
  if (!key) throw new Error('PROVIDER_SECRET_ENCRYPTION_NOT_CONFIGURED');
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(source.secretIv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(source.secretTag, 'base64'));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(source.secretCiphertext, 'base64')),
    decipher.final(),
  ]);
  return plaintext.toString('utf8');
}
