import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { PrismaClient } from '@prisma/client';
import { createHash, randomBytes } from 'node:crypto';
import { decryptMetaSecret, encryptMetaSecret, metaSecretEncryptionConfigured } from './metaSecrets.js';

type AuthenticateHook = (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
type JwtClaims = { sub: string };

const GRAPH_VERSION = (process.env.META_GRAPH_VERSION || 'v26.0').trim();
const graphBase = () => `https://graph.facebook.com/${GRAPH_VERSION}`;

function cfg() {
  return {
    appId: process.env.META_APP_ID?.trim() || '',
    appSecret: process.env.META_APP_SECRET?.trim() || '',
    redirectUri: process.env.META_REDIRECT_URI?.trim() || '',
  };
}

function configured() {
  const c = cfg();
  return Boolean(c.appId && c.appSecret && c.redirectUri && metaSecretEncryptionConfigured());
}

function stateHash(value: string) {
  return createHash('sha256').update(value).digest('hex');
}

async function jsonFetch(url: string | URL, init?: RequestInit) {
  const response = await fetch(url, init);
  const text = await response.text();
  let json: any = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  if (!response.ok || json?.error) {
    const message = json?.error?.message || json?.error_description || `Meta request failed (${response.status})`;
    const error = new Error(message);
    (error as any).meta = json;
    throw error;
  }
  return json;
}

function connectionJson(row: any) {
  return {
    id: row.id,
    status: row.status,
    facebookUserId: row.facebookUserId,
    facebookUserName: row.facebookUserName,
    pageId: row.pageId,
    pageName: row.pageName,
    pageTasks: Array.isArray(row.pageTasks) ? row.pageTasks : [],
    instagramUserId: row.instagramUserId,
    instagramUsername: row.instagramUsername,
    instagramName: row.instagramName,
    instagramProfilePictureUrl: row.instagramProfilePictureUrl,
    permissions: Array.isArray(row.permissions) ? row.permissions : [],
    adAccounts: Array.isArray(row.adAccounts) ? row.adAccounts : [],
    advertisingReady: Array.isArray(row.pageTasks) && row.pageTasks.includes('ADVERTISE'),
    lastValidatedAt: row.lastValidatedAt,
    updatedAt: row.updatedAt,
  };
}

function htmlPage(title: string, body: string, ok = true) {
  const color = ok ? '#1686ff' : '#d74b4b';
  return `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
  <body style="font-family:Arial,sans-serif;background:#f5f7fb;margin:0;padding:32px;color:#182334"><div style="max-width:520px;margin:10vh auto;background:#fff;border-radius:20px;padding:28px;box-shadow:0 12px 40px #0001;text-align:center">
  <div style="width:54px;height:54px;border-radius:18px;background:${color};color:#fff;display:grid;place-items:center;margin:0 auto 16px;font-size:28px">${ok ? '✓' : '!'}</div><h2>${title}</h2><p style="line-height:1.8;color:#607083">${body}</p><p style="font-size:13px;color:#8591a2">اکنون می‌توانید به VELIXEO برگردید.<br>Return to VELIXEO.</p></div></body></html>`;
}

export function registerMetaConnectionRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
) {
  app.get('/api/v1/promotions/meta/config', async () => ({
    configured: configured(),
    graphVersion: GRAPH_VERSION,
    loginMode: 'META_BUSINESS_OAUTH',
    passwordStored: false,
  }));

  app.get('/api/v1/promotions/meta/connections', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const rows = await prisma.metaConnection.findMany({
      where: { userId, status: { not: 'REVOKED' } },
      orderBy: { updatedAt: 'desc' },
    });
    return { configured: configured(), connections: rows.map(connectionJson) };
  });

  app.post('/api/v1/promotions/meta/connect', { preHandler: authenticate }, async (request, reply) => {
    if (!configured()) {
      const c = cfg();
      return reply.code(503).send({
        error: 'meta_login_not_configured',
        missing: [
          ifMissing(c.appId, 'META_APP_ID'),
          ifMissing(c.appSecret, 'META_APP_SECRET'),
          ifMissing(c.redirectUri, 'META_REDIRECT_URI'),
          ...(!metaSecretEncryptionConfigured() ? ['ADMIN_SECRET_ENCRYPTION_KEY'] : []),
        ].filter(Boolean),
      });
    }
    const userId = (request.user as JwtClaims).sub;
    const state = randomBytes(32).toString('base64url');
    await prisma.metaOAuthSession.create({
      data: {
        userId,
        stateHash: stateHash(state),
        expiresAt: new Date(Date.now() + 15 * 60 * 1000),
        metadata: { source: 'VELIXEO_PROMOTIONS', graphVersion: GRAPH_VERSION },
      },
    });
    const c = cfg();
    const auth = new URL(`https://www.facebook.com/${GRAPH_VERSION}/dialog/oauth`);
    auth.searchParams.set('client_id', c.appId);
    auth.searchParams.set('redirect_uri', c.redirectUri);
    auth.searchParams.set('state', state);
    auth.searchParams.set('response_type', 'code');
    auth.searchParams.set('scope', [
      'pages_show_list',
      'pages_read_engagement',
      'instagram_basic',
      'ads_read',
      'ads_management',
      'business_management',
    ].join(','));
    auth.searchParams.set('auth_type', 'rerequest');
    auth.searchParams.set('return_scopes', 'true');
    return { url: auth.toString(), expiresInSeconds: 900 };
  });

  app.get('/api/v1/promotions/meta/callback', async (request, reply) => {
    const query = request.query as Record<string, string | undefined>;
    if (query.error) {
      return reply.type('text/html; charset=utf-8').send(htmlPage(
        'اتصال انجام نشد',
        'مجوز اتصال Meta تأیید نشد. می‌توانید دوباره از داخل VELIXEO تلاش کنید.',
        false,
      ));
    }
    const state = String(query.state || '');
    const code = String(query.code || '');
    if (!state || !code) {
      return reply.code(400).type('text/html; charset=utf-8').send(htmlPage('درخواست نامعتبر است', 'کد یا state ورود Meta موجود نیست.', false));
    }
    const session = await prisma.metaOAuthSession.findUnique({ where: { stateHash: stateHash(state) } });
    if (!session || session.consumedAt || session.expiresAt.getTime() < Date.now()) {
      return reply.code(400).type('text/html; charset=utf-8').send(htmlPage('لینک منقضی شده', 'لطفاً از داخل VELIXEO دوباره «ورود با اینستاگرام» را بزنید.', false));
    }
    if (!configured()) {
      return reply.code(503).type('text/html; charset=utf-8').send(htmlPage('تنظیمات Meta کامل نیست', 'تنظیمات سرور VELIXEO برای Meta هنوز کامل نشده است.', false));
    }

    try {
      const c = cfg();
      const tokenUrl = new URL(`${graphBase()}/oauth/access_token`);
      tokenUrl.searchParams.set('client_id', c.appId);
      tokenUrl.searchParams.set('client_secret', c.appSecret);
      tokenUrl.searchParams.set('redirect_uri', c.redirectUri);
      tokenUrl.searchParams.set('code', code);
      const shortToken = await jsonFetch(tokenUrl);
      const shortAccessToken = String(shortToken.access_token || '');
      if (!shortAccessToken) throw new Error('Meta did not return an access token.');

      const longUrl = new URL(`${graphBase()}/oauth/access_token`);
      longUrl.searchParams.set('grant_type', 'fb_exchange_token');
      longUrl.searchParams.set('client_id', c.appId);
      longUrl.searchParams.set('client_secret', c.appSecret);
      longUrl.searchParams.set('fb_exchange_token', shortAccessToken);
      let tokenData: any;
      try { tokenData = await jsonFetch(longUrl); } catch { tokenData = shortToken; }
      const userAccessToken = String(tokenData.access_token || shortAccessToken);
      const tokenExpiresAt = Number(tokenData.expires_in || shortToken.expires_in || 0) > 0
        ? new Date(Date.now() + Number(tokenData.expires_in || shortToken.expires_in) * 1000)
        : null;

      const [me, permissions, pages] = await Promise.all([
        jsonFetch(`${graphBase()}/me?fields=id,name&access_token=${encodeURIComponent(userAccessToken)}`),
        jsonFetch(`${graphBase()}/me/permissions?access_token=${encodeURIComponent(userAccessToken)}`),
        jsonFetch(`${graphBase()}/me/accounts?fields=id,name,access_token,tasks,instagram_business_account{id,username,name,profile_picture_url}&limit=100&access_token=${encodeURIComponent(userAccessToken)}`),
      ]);
      let adAccounts: any[] = [];
      try {
        const ads = await jsonFetch(`${graphBase()}/me/adaccounts?fields=id,name,account_status,currency,timezone_name,business{id,name}&limit=100&access_token=${encodeURIComponent(userAccessToken)}`);
        adAccounts = Array.isArray(ads.data) ? ads.data : [];
      } catch {}

      const granted = Array.isArray(permissions.data)
        ? permissions.data.filter((p: any) => p.status === 'granted').map((p: any) => p.permission)
        : [];
      const pageRows = Array.isArray(pages.data) ? pages.data : [];
      const withInstagram = pageRows.filter((page: any) => page?.instagram_business_account?.id);
      if (!withInstagram.length) {
        await prisma.metaOAuthSession.update({ where: { id: session.id }, data: { consumedAt: new Date() } });
        return reply.type('text/html; charset=utf-8').send(htmlPage(
          'حساب حرفه‌ای اینستاگرام پیدا نشد',
          'این ورود موفق بود، اما هیچ Instagram Professional متصل به Pageهای این حساب پیدا نشد. حساب Instagram باید Business یا Creator باشد و به یک Facebook Page متصل باشد.',
          false,
        ));
      }

      const encryptedUser = encryptMetaSecret(userAccessToken);
      for (const page of withInstagram) {
        const ig = page.instagram_business_account;
        const encryptedPage = page.access_token ? encryptMetaSecret(String(page.access_token)) : null;
        await prisma.metaConnection.upsert({
          where: { userId_instagramUserId: { userId: session.userId, instagramUserId: String(ig.id) } },
          create: {
            userId: session.userId,
            status: 'CONNECTED',
            facebookUserId: String(me.id || '') || null,
            facebookUserName: String(me.name || '') || null,
            pageId: String(page.id || '') || null,
            pageName: String(page.name || '') || null,
            pageTasks: Array.isArray(page.tasks) ? page.tasks : [],
            instagramUserId: String(ig.id),
            instagramUsername: String(ig.username || '') || null,
            instagramName: String(ig.name || '') || null,
            instagramProfilePictureUrl: String(ig.profile_picture_url || '') || null,
            permissions: granted,
            adAccounts,
            userTokenCiphertext: encryptedUser.ciphertext,
            userTokenIv: encryptedUser.iv,
            userTokenTag: encryptedUser.tag,
            pageTokenCiphertext: encryptedPage?.ciphertext || null,
            pageTokenIv: encryptedPage?.iv || null,
            pageTokenTag: encryptedPage?.tag || null,
            tokenExpiresAt,
            lastValidatedAt: new Date(),
            metadata: { graphVersion: GRAPH_VERSION, loginMode: 'META_BUSINESS_OAUTH' },
          },
          update: {
            status: 'CONNECTED',
            facebookUserId: String(me.id || '') || null,
            facebookUserName: String(me.name || '') || null,
            pageId: String(page.id || '') || null,
            pageName: String(page.name || '') || null,
            pageTasks: Array.isArray(page.tasks) ? page.tasks : [],
            instagramUsername: String(ig.username || '') || null,
            instagramName: String(ig.name || '') || null,
            instagramProfilePictureUrl: String(ig.profile_picture_url || '') || null,
            permissions: granted,
            adAccounts,
            userTokenCiphertext: encryptedUser.ciphertext,
            userTokenIv: encryptedUser.iv,
            userTokenTag: encryptedUser.tag,
            pageTokenCiphertext: encryptedPage?.ciphertext || null,
            pageTokenIv: encryptedPage?.iv || null,
            pageTokenTag: encryptedPage?.tag || null,
            tokenExpiresAt,
            lastValidatedAt: new Date(),
            metadata: { graphVersion: GRAPH_VERSION, loginMode: 'META_BUSINESS_OAUTH' },
          },
        });
      }
      await prisma.metaOAuthSession.update({ where: { id: session.id }, data: { consumedAt: new Date() } });
      return reply.type('text/html; charset=utf-8').send(htmlPage(
        'اینستاگرام با موفقیت متصل شد',
        `${withInstagram.length} حساب حرفه‌ای اینستاگرام به VELIXEO متصل شد. اطلاعات اتصال و مجوزها در پنل ادمین قابل مشاهده است.`,
      ));
    } catch (error) {
      request.log.error({ error, oauthSessionId: session.id }, 'Meta OAuth callback failed');
      return reply.code(502).type('text/html; charset=utf-8').send(htmlPage(
        'اتصال Meta کامل نشد',
        'Meta پاسخ لازم را نداد یا یکی از مجوزهای موردنیاز موجود نبود. دوباره تلاش کنید.',
        false,
      ));
    }
  });

  app.get('/api/v1/promotions/meta/connections/:id/media', { preHandler: authenticate }, async (request, reply) => {
    const userId = (request.user as JwtClaims).sub;
    const id = String((request.params as any).id || '');
    const row = await prisma.metaConnection.findFirst({ where: { id, userId, status: 'CONNECTED' } });
    if (!row || !row.instagramUserId) return reply.code(404).send({ error: 'meta_connection_not_found' });
    const token = decryptMetaSecret({
      ciphertext: row.pageTokenCiphertext || row.userTokenCiphertext,
      iv: row.pageTokenIv || row.userTokenIv,
      tag: row.pageTokenTag || row.userTokenTag,
    });
    if (!token) return reply.code(409).send({ error: 'meta_connection_token_missing' });
    try {
      const url = new URL(`${graphBase()}/${encodeURIComponent(row.instagramUserId)}/media`);
      url.searchParams.set('fields', 'id,caption,media_type,media_product_type,media_url,thumbnail_url,permalink,timestamp');
      url.searchParams.set('limit', '50');
      url.searchParams.set('access_token', token);
      const data = await jsonFetch(url);
      const media = (Array.isArray(data.data) ? data.data : []).map((item: any) => ({
        id: String(item.id || ''),
        caption: String(item.caption || ''),
        mediaType: String(item.media_type || ''),
        mediaProductType: String(item.media_product_type || ''),
        mediaUrl: String(item.media_url || ''),
        thumbnailUrl: String(item.thumbnail_url || item.media_url || ''),
        permalink: String(item.permalink || ''),
        timestamp: item.timestamp || null,
      }));
      await prisma.metaConnection.update({ where: { id: row.id }, data: { lastValidatedAt: new Date() } });
      return { connection: connectionJson(row), media };
    } catch (error) {
      request.log.warn({ error, metaConnectionId: row.id }, 'Meta media fetch failed');
      return reply.code(502).send({ error: 'meta_media_fetch_failed' });
    }
  });

  app.post('/api/v1/promotions/meta/connections/:id/disconnect', { preHandler: authenticate }, async (request, reply) => {
    const userId = (request.user as JwtClaims).sub;
    const id = String((request.params as any).id || '');
    const row = await prisma.metaConnection.findFirst({ where: { id, userId } });
    if (!row) return reply.code(404).send({ error: 'meta_connection_not_found' });
    await prisma.metaConnection.update({
      where: { id },
      data: {
        status: 'REVOKED',
        userTokenCiphertext: null, userTokenIv: null, userTokenTag: null,
        pageTokenCiphertext: null, pageTokenIv: null, pageTokenTag: null,
      },
    });
    return { ok: true };
  });
}

function ifMissing(value: string, key: string) {
  return value ? '' : key;
}
