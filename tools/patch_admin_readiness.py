from pathlib import Path

path = Path('backend/src/adminExtended.ts')
source = path.read_text()

nav_anchor = "    ['/admin/settings', 'تنظیمات سیستم', 'settings'],\n"
nav_line = "    ['/admin/readiness', 'آمادگی سیستم', 'readiness'],\n"
if nav_line not in source:
    if nav_anchor not in source:
        raise SystemExit('admin nav anchor not found')
    source = source.replace(nav_anchor, nav_anchor + nav_line, 1)

route_anchor = "  app.get('/admin/reports', async (request, reply) => {\n"
if "app.get('/admin/readiness'" not in source:
    if route_anchor not in source:
        raise SystemExit('admin reports route anchor not found')
    route = r'''  app.get('/admin/readiness', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;

    let databaseHealthy = true;
    try {
      await prisma.$queryRaw`SELECT 1`;
    } catch {
      databaseHealthy = false;
    }

    const googleConfigured = Boolean(process.env.GOOGLE_WEB_CLIENT_ID?.trim());
    const providerEncryption = providerSecretEncryptionConfigured();
    const publicBaseUrl = process.env.PUBLIC_BASE_URL?.trim() || '';
    const publicBaseHttps = publicBaseUrl.startsWith('https://');
    const hesabPayKeyConfigured = Boolean(process.env.HESABPAY_API_KEY?.trim());
    const hesabPayEnvironment = process.env.HESABPAY_ENVIRONMENT?.trim() || 'sandbox';
    const hesabPayConfigured = hesabPayKeyConfigured && publicBaseHttps;
    const webhookUrl = publicBaseHttps
      ? `${publicBaseUrl.replace(/\/$/, '')}/api/v1/payments/hesabpay/webhook`
      : '—';

    const [providerCount, encryptedProviderCount] = await Promise.all([
      prisma.provider.count(),
      prisma.provider.count({
        where: {
          secretCiphertext: { not: null },
          secretIv: { not: null },
          secretTag: { not: null },
        },
      }),
    ]);

    const checks = [
      {
        label: 'Database',
        ok: databaseHealthy,
        detail: databaseHealthy ? 'اتصال PostgreSQL برقرار است.' : 'اتصال PostgreSQL ناموفق است.',
      },
      {
        label: 'Google Sign-In',
        ok: googleConfigured,
        detail: googleConfigured
          ? 'Web Client ID روی سرور تنظیم شده است.'
          : 'GOOGLE_WEB_CLIENT_ID روی سرور تنظیم نشده است.',
      },
      {
        label: 'Provider Secret Encryption',
        ok: providerEncryption,
        detail: providerEncryption
          ? 'AES-256-GCM برای ذخیره کلید Provider آماده است.'
          : 'ADMIN_SECRET_ENCRYPTION_KEY تنظیم نشده یا معتبر نیست.',
      },
      {
        label: 'Public HTTPS URL',
        ok: publicBaseHttps,
        detail: publicBaseHttps
          ? 'PUBLIC_BASE_URL برای callback/webhook با HTTPS تنظیم شده است.'
          : 'PUBLIC_BASE_URL امن هنوز تنظیم نشده است.',
      },
      {
        label: 'HesabPay',
        ok: hesabPayConfigured,
        detail: hesabPayConfigured
          ? `Gateway server config موجود است (${hesabPayEnvironment}).`
          : 'API Key و Public HTTPS URL هر دو برای فعال شدن پرداخت لازم هستند.',
      },
    ];

    const readyCount = checks.filter((item) => item.ok).length;
    const body = `<div class="warn">این صفحه فقط وضعیت «تنظیم شده / تنظیم نشده» را نشان می‌دهد و هیچ Secret، API Key یا Client ID را نمایش نمی‌دهد.</div><div class="statgrid" style="margin-top:14px"><div class="stat"><small>چک‌های آماده</small><b>${readyCount}/${checks.length}</b></div><div class="stat"><small>Provider ثبت‌شده</small><b>${providerCount}</b></div><div class="stat"><small>Provider با Secret رمزگذاری‌شده</small><b>${encryptedProviderCount}</b></div><div class="stat"><small>HesabPay Environment</small><b style="font-size:17px">${esc(hesabPayEnvironment)}</b></div></div><div class="card" style="margin-top:16px"><h3 class="section">Production Readiness</h3>${checks.map((item) => `<div class="note" style="display:flex;gap:12px;align-items:flex-start;margin-bottom:9px"><span class="badge ${item.ok ? 'okbadge' : 'badbadge'}">${item.ok ? 'READY' : 'MISSING'}</span><div><b>${esc(item.label)}</b><div class="muted" style="margin-top:4px">${esc(item.detail)}</div></div></div>`).join('')}</div><div class="card"><h3 class="section">HesabPay Webhook</h3><div class="muted">آدرس Webhook فقط وقتی PUBLIC_BASE_URL امن تنظیم باشد ساخته می‌شود.</div><div class="secret mono" style="margin-top:10px">${esc(webhookUrl)}</div><div class="muted" style="margin-top:10px">شارژ Wallet فقط بعد از Verify امضا + تطبیق مبلغ + Ledger idempotent انجام می‌شود؛ Redirect موفق به‌تنهایی Wallet را تغییر نمی‌دهد.</div></div>`;

    return reply.type('text/html; charset=utf-8').send(
      adminShell({ title: 'آمادگی سیستم', admin, active: 'readiness', body }),
    );
  });

'''
    source = source.replace(route_anchor, route + route_anchor, 1)

path.write_text(source)
