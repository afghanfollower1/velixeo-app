from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Missing anchor: {label}')
    return text.replace(old, new, 1)


path = Path('backend/src/adminExtended.ts')
text = path.read_text()

text = replace_once(
    text,
    "  UserRole,\n  UserStatus,",
    "  UserRole,\n  UserStatus,\n  WalletEntryType,",
    'wallet entry import',
)

text = replace_once(
    text,
    "    ['/admin/audit', 'گزارش مدیر', 'audit'],",
    "    ['/admin/reports', 'گزارش مالی', 'reports'],\n    ['/admin/audit', 'گزارش مدیر', 'audit'],",
    'reports navigation',
)

text = replace_once(
    text,
    "    self_protected: ['نمی‌توانی حساب مدیریتی خودت را تعلیق یا از نقش ADMIN خارج کنی.', true],",
    "    self_protected: ['نمی‌توانی حساب مدیریتی خودت را تعلیق یا از نقش ADMIN خارج کنی.', true],\n    refunded: ['مبلغ سفارش با Ledger به کیف پول کاربر برگشت داده شد.', false],\n    already_refunded: ['این سفارش قبلاً Refund شده است.', true],",
    'refund messages',
)

service_form_anchor = "<div class=\"field\"><label>English description</label><textarea name=\"descriptionEn\">${esc(s?.descriptionEn || '')}</textarea></div><div class=\"field\"><label>ترتیب نمایش</label>"
service_form_new = "<div class=\"field\"><label>English description</label><textarea name=\"descriptionEn\">${esc(s?.descriptionEn || '')}</textarea></div><div class=\"field\"><label>Metadata JSON (تنظیمات پیشرفته سرویس)</label><textarea class=\"mono\" name=\"metadata\" placeholder='{\"country\":\"afghanistan\",\"operator\":\"...\"}'>${esc(s?.metadata ? JSON.stringify(s.metadata, null, 2) : '')}</textarea></div><div class=\"field\"><label>ترتیب نمایش</label>"
text = replace_once(text, service_form_anchor, service_form_new, 'service metadata form')

service_data_anchor = "        maxQty: maxRaw ? Math.max(1, intValue(body, 'maxQty', 1)) : null,\n      };"
service_data_new = "        maxQty: maxRaw ? Math.max(1, intValue(body, 'maxQty', 1)) : null,\n        metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,\n      };"
text = replace_once(text, service_data_anchor, service_data_new, 'service metadata save')

route_form_anchor = "<div class=\"grid3\"><div class=\"field\"><label>Priority</label><input name=\"priority\" type=\"number\" value=\"100\"></div><div class=\"field\"><label>Cost AFN اختیاری</label><input name=\"costAfn\" type=\"number\" min=\"0\"></div><div class=\"field\"><label>Markup % اختیاری</label><input name=\"markup\" inputmode=\"decimal\"></div></div><label class=\"check\">"
route_form_new = "<div class=\"grid3\"><div class=\"field\"><label>Priority</label><input name=\"priority\" type=\"number\" value=\"100\"></div><div class=\"field\"><label>Cost AFN اختیاری</label><input name=\"costAfn\" type=\"number\" min=\"0\"></div><div class=\"field\"><label>Markup % اختیاری</label><input name=\"markup\" inputmode=\"decimal\"></div></div><div class=\"field\"><label>Route Metadata JSON</label><textarea class=\"mono\" name=\"metadata\" placeholder='{\"countryCode\":\"af\",\"operator\":\"any\"}'></textarea></div><label class=\"check\">"
text = replace_once(text, route_form_anchor, route_form_new, 'route metadata form')

route_update_anchor = "          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,\n        },\n        create: {"
route_update_new = "          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,\n          metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,\n        },\n        create: {"
text = replace_once(text, route_update_anchor, route_update_new, 'route metadata update')
route_create_anchor = "          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,\n        },\n      });"
route_create_new = "          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,\n          metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,\n        },\n      });"
text = replace_once(text, route_create_anchor, route_create_new, 'route metadata create')

order_row_anchor = "<td><form method=\"post\" action=\"/admin/orders/status\" class=\"row\"><input type=\"hidden\" name=\"id\" value=\"${esc(o.id)}\"><select name=\"status\">${selectOptions(Object.values(OrderStatus).filter((x) => x !== 'REFUNDED'), o.status)}</select><button class=\"ghost\" type=\"submit\">ثبت</button></form></td><td>${faDate(o.createdAt)}</td>"
order_row_new = "<td><form method=\"post\" action=\"/admin/orders/status\" class=\"row\"><input type=\"hidden\" name=\"id\" value=\"${esc(o.id)}\"><select name=\"status\">${selectOptions(Object.values(OrderStatus).filter((x) => x !== 'REFUNDED'), o.status)}</select><button class=\"ghost\" type=\"submit\">ثبت</button></form>${o.status !== OrderStatus.REFUNDED ? `<form method=\"post\" action=\"/admin/orders/refund\" style=\"margin-top:6px\"><input type=\"hidden\" name=\"id\" value=\"${esc(o.id)}\"><button class=\"danger\" type=\"submit\">Refund کامل</button></form>` : '<span class=\"badge okbadge\">Refunded</span>'}</td><td>${faDate(o.createdAt)}</td>"
text = replace_once(text, order_row_anchor, order_row_new, 'order refund action')

refund_route_anchor = "  app.get('/admin/payments', async (request, reply) => {"
refund_route = r'''  app.post('/admin/orders/refund', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const orderId = text(request.body as AnyBody, 'id');
    if (!orderId) return reply.code(303).redirect('/admin/orders?msg=invalid');
    try {
      const refund = await prisma.$transaction(
        async (tx) => {
          const order = await tx.order.findUnique({ where: { id: orderId } });
          if (!order) throw new Error('ORDER_NOT_FOUND');
          if (order.status === OrderStatus.REFUNDED) throw new Error('ALREADY_REFUNDED');

          const existing = await tx.walletEntry.findUnique({
            where: { idempotencyKey: `order-refund-${order.id}` },
          });
          if (existing) throw new Error('ALREADY_REFUNDED');

          const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');
          const nextBalance = wallet.balanceAfn + order.totalAmountAfn;

          await tx.wallet.update({
            where: { id: wallet.id },
            data: { balanceAfn: nextBalance },
          });
          const entry = await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.REFUND,
              amountAfn: order.totalAmountAfn,
              balanceAfterAfn: nextBalance,
              description: `Refund order ${order.id}`,
              idempotencyKey: `order-refund-${order.id}`,
              referenceType: 'ORDER_REFUND',
              referenceId: order.id,
              metadata: { adminUserId: admin.id },
            },
          });
          await tx.order.update({
            where: { id: order.id },
            data: { status: OrderStatus.REFUNDED },
          });
          return { order, entry };
        },
        { isolationLevel: 'Serializable' },
      );
      await audit(
        prisma,
        admin.id,
        'ORDER_REFUND',
        'Order',
        orderId,
        `Refunded ${refund.order.totalAmountAfn.toString()} AFN`,
        { walletEntryId: refund.entry.id, userId: refund.order.userId },
      );
      return reply.code(303).redirect('/admin/orders?msg=refunded');
    } catch (error) {
      if (error instanceof Error && error.message === 'ALREADY_REFUNDED') {
        return reply.code(303).redirect('/admin/orders?msg=already_refunded');
      }
      if (error instanceof Error && error.message === 'ORDER_NOT_FOUND') {
        return reply.code(303).redirect('/admin/orders?msg=not_found');
      }
      throw error;
    }
  });

'''
text = replace_once(text, refund_route_anchor, refund_route + refund_route_anchor, 'refund route')

report_anchor = "  app.get('/admin/audit', async (request, reply) => {"
report_route = r'''  app.get('/admin/reports', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const start = new Date();
    start.setUTCDate(start.getUTCDate() - 30);
    const [completed, refunded, paymentPaid, newUsers, walletSum, byCategory] = await Promise.all([
      prisma.order.aggregate({
        where: { status: { in: [OrderStatus.COMPLETED, OrderStatus.PARTIAL] }, createdAt: { gte: start } },
        _sum: { totalAmountAfn: true, providerCostAfn: true },
        _count: { _all: true },
      }),
      prisma.order.aggregate({
        where: { status: OrderStatus.REFUNDED, updatedAt: { gte: start } },
        _sum: { totalAmountAfn: true },
        _count: { _all: true },
      }),
      prisma.paymentTransaction.aggregate({
        where: { status: 'PAID', paidAt: { gte: start } },
        _sum: { amountAfn: true },
        _count: { _all: true },
      }),
      prisma.user.count({ where: { createdAt: { gte: start } } }),
      prisma.wallet.aggregate({ _sum: { balanceAfn: true } }),
      prisma.order.groupBy({
        by: ['category'],
        where: { createdAt: { gte: start } },
        _count: { _all: true },
        _sum: { totalAmountAfn: true },
        orderBy: { _count: { category: 'desc' } },
      }),
    ]);
    const sales = completed._sum.totalAmountAfn ?? 0n;
    const cost = completed._sum.providerCostAfn ?? 0n;
    const profit = sales - cost;
    const body = `<div class="muted" style="margin-bottom:12px">خلاصه ۳۰ روز اخیر — محاسبات مالی بر پایه AFN</div><div class="statgrid"><div class="stat"><small>فروش تکمیل‌شده</small><b>${fmtAfn(sales)}</b><span class="muted">${completed._count._all} سفارش</span></div><div class="stat"><small>هزینه Provider ثبت‌شده</small><b>${fmtAfn(cost)}</b></div><div class="stat"><small>سود ناخالص ثبت‌شده</small><b>${fmtAfn(profit)}</b></div><div class="stat"><small>Refund</small><b>${fmtAfn(refunded._sum.totalAmountAfn ?? 0n)}</b><span class="muted">${refunded._count._all} سفارش</span></div></div><div class="grid2" style="margin-top:14px"><div class="stat"><small>پرداخت‌های تأییدشده</small><b>${fmtAfn(paymentPaid._sum.amountAfn ?? 0n)}</b><span class="muted">${paymentPaid._count._all} تراکنش</span></div><div class="stat"><small>موجودی کل Walletها</small><b>${fmtAfn(walletSum._sum.balanceAfn ?? 0n)}</b><span class="muted">${newUsers} کاربر جدید</span></div></div><div class="card table" style="margin-top:16px"><h3 class="section">عملکرد دسته‌ها</h3><table><thead><tr><th>دسته</th><th>تعداد سفارش</th><th>مبلغ</th></tr></thead><tbody>${byCategory.map((row) => `<tr><td>${row.category}</td><td>${row._count._all}</td><td>${fmtAfn(row._sum.totalAmountAfn ?? 0n)}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">داده‌ای وجود ندارد.</td></tr>'}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'گزارش مالی', admin, active: 'reports', body }));
  });

'''
text = replace_once(text, report_anchor, report_route + report_anchor, 'reports route')

path.write_text(text)
