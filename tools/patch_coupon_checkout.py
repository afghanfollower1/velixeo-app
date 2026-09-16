from pathlib import Path


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    if text.count(old) != 1:
        raise SystemExit(f'anchor not unique in {path}: {text.count(old)}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# Backend coupon-aware social checkout.
replace_once(
    'backend/src/socialRoutes.ts',
    "} from './smmPanelAdapter.js';\n",
    "} from './smmPanelAdapter.js';\nimport { claimCoupon, quoteCoupon, releaseCoupon } from './couponPricing.js';\n",
)
replace_once(
    'backend/src/socialRoutes.ts',
    "  clientRequestId: z.string().uuid(),\n  parameters: z.record(\n",
    "  clientRequestId: z.string().uuid(),\n  couponCode: z.string().trim().max(80).optional().nullable(),\n  parameters: z.record(\n",
)
replace_once(
    'backend/src/socialRoutes.ts',
    "const quoteSchema = z.object({\n  serviceId: z.string().uuid(),\n  parameters: z.record(\n",
    "const quoteSchema = z.object({\n  serviceId: z.string().uuid(),\n  couponCode: z.string().trim().max(80).optional().nullable(),\n  parameters: z.record(\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "    const totalAmountAfn = ceilDiv(rateAfn * BigInt(quantity), BigInt(Math.max(1, service.priceUnit)));\n    return {\n      quantity,\n      rateAfn: rateAfn.toString(),\n      priceUnit: service.priceUnit,\n      totalAmountAfn: totalAmountAfn.toString(),\n    };\n",
    "    const subtotalAmountAfn = ceilDiv(rateAfn * BigInt(quantity), BigInt(Math.max(1, service.priceUnit)));\n    let couponPrice;\n    try {\n      couponPrice = await quoteCoupon(prisma, parsed.data.couponCode, subtotalAmountAfn);\n    } catch (error) {\n      const code = error instanceof Error ? error.message.toLowerCase() : 'coupon_invalid';\n      return reply.code(409).send({ error: code });\n    }\n    return {\n      quantity,\n      rateAfn: rateAfn.toString(),\n      priceUnit: service.priceUnit,\n      subtotalAmountAfn: couponPrice.subtotalAfn.toString(),\n      discountAmountAfn: couponPrice.discountAfn.toString(),\n      totalAmountAfn: couponPrice.totalAfn.toString(),\n      couponCode: couponPrice.couponCode,\n    };\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "    const totalAmountAfn = ceilDiv(\n      customerRate * BigInt(quantity),\n      BigInt(Math.max(1, service.priceUnit)),\n    );\n    if (totalAmountAfn <= 0n) return reply.code(409).send({ error: 'service_price_invalid' });\n\n    let order;\n",
    "    const subtotalAmountAfn = ceilDiv(\n      customerRate * BigInt(quantity),\n      BigInt(Math.max(1, service.priceUnit)),\n    );\n    if (subtotalAmountAfn <= 0n) return reply.code(409).send({ error: 'service_price_invalid' });\n    let couponPrice;\n    try {\n      couponPrice = await quoteCoupon(prisma, parsed.data.couponCode, subtotalAmountAfn);\n    } catch (error) {\n      const code = error instanceof Error ? error.message.toLowerCase() : 'coupon_invalid';\n      return reply.code(409).send({ error: code });\n    }\n    const totalAmountAfn = couponPrice.totalAfn;\n\n    let order;\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "          const duplicate = await tx.order.findUnique({ where: { clientRequestId: parsed.data.clientRequestId } });\n          if (duplicate) return duplicate;\n          const wallet = await tx.wallet.findUnique({ where: { userId } });\n",
    "          const duplicate = await tx.order.findUnique({ where: { clientRequestId: parsed.data.clientRequestId } });\n          if (duplicate) return duplicate;\n          await claimCoupon(tx, couponPrice);\n          const wallet = await tx.wallet.findUnique({ where: { userId } });\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "                refillDays: service.refillDays,\n              },\n",
    "                refillDays: service.refillDays,\n                couponCode: couponPrice.couponCode,\n                couponId: couponPrice.couponId,\n                subtotalAmountAfn: couponPrice.subtotalAfn.toString(),\n                discountAmountAfn: couponPrice.discountAfn.toString(),\n              },\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "      if (expectedCost != null && expectedCost > totalAmountAfn && service.routes.length > 1) continue;\n",
    "      if (expectedCost != null && expectedCost > subtotalAmountAfn && service.routes.length > 1) continue;\n",
)

replace_once(
    'backend/src/socialRoutes.ts',
    "    await prisma.order.update({\n      where: { id: order.id },\n      data: { status: OrderStatus.FAILED, failureReason: explicitFailure },\n    });\n",
    "    await prisma.order.update({\n      where: { id: order.id },\n      data: { status: OrderStatus.FAILED, failureReason: explicitFailure },\n    });\n    await releaseCoupon(prisma, couponPrice.couponId);\n",
)

# Flutter social quote model.
replace_once(
    'lib/social/social_models.dart',
    "    required this.totalAmountAfn,\n  });\n\n  final int quantity;\n  final int rateAfn;\n  final int priceUnit;\n  final int totalAmountAfn;\n",
    "    required this.totalAmountAfn,\n    required this.subtotalAmountAfn,\n    required this.discountAmountAfn,\n    this.couponCode,\n  });\n\n  final int quantity;\n  final int rateAfn;\n  final int priceUnit;\n  final int subtotalAmountAfn;\n  final int discountAmountAfn;\n  final int totalAmountAfn;\n  final String? couponCode;\n",
)
replace_once(
    'lib/social/social_models.dart',
    "        totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,\n      );\n",
    "        subtotalAmountAfn: int.tryParse('${json['subtotalAmountAfn'] ?? json['totalAmountAfn']}') ?? 0,\n        discountAmountAfn: int.tryParse('${json['discountAmountAfn']}') ?? 0,\n        totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,\n        couponCode: json['couponCode'] as String?,\n      );\n",
)

# API client accepts optional coupon code.
replace_once(
    'lib/core/api_service.dart',
    "  Future<SocialQuote> socialQuote({\n    required String serviceId,\n    required Map<String, dynamic> parameters,\n  }) async {\n",
    "  Future<SocialQuote> socialQuote({\n    required String serviceId,\n    required Map<String, dynamic> parameters,\n    String? couponCode,\n  }) async {\n",
)
replace_once(
    'lib/core/api_service.dart',
    "      body: {'serviceId': serviceId, 'parameters': parameters},\n      auth: true,\n",
    "      body: {\n        'serviceId': serviceId,\n        'parameters': parameters,\n        if (couponCode?.trim().isNotEmpty == true) 'couponCode': couponCode!.trim(),\n      },\n      auth: true,\n",
)
replace_once(
    'lib/core/api_service.dart',
    "    required String clientRequestId,\n    required Map<String, dynamic> parameters,\n  }) async {\n",
    "    required String clientRequestId,\n    required Map<String, dynamic> parameters,\n    String? couponCode,\n  }) async {\n",
)
replace_once(
    'lib/core/api_service.dart',
    "        'parameters': parameters,\n      },\n      auth: true,\n",
    "        'parameters': parameters,\n        if (couponCode?.trim().isNotEmpty == true) 'couponCode': couponCode!.trim(),\n      },\n      auth: true,\n",
)

# Flutter social panel coupon field and pricing display.
replace_once(
    'lib/social/social_panel.dart',
    "  final Map<String, TextEditingController> fields = {};\n",
    "  final Map<String, TextEditingController> fields = {};\n  final coupon = TextEditingController();\n",
)
replace_once(
    'lib/social/social_panel.dart',
    "  void initState() {\n    super.initState();\n    load();\n  }\n",
    "  void initState() {\n    super.initState();\n    coupon.addListener(scheduleQuote);\n    load();\n  }\n",
)
replace_once(
    'lib/social/social_panel.dart',
    "    for (final controller in fields.values) {\n      controller.dispose();\n    }\n    super.dispose();\n",
    "    for (final controller in fields.values) {\n      controller.dispose();\n    }\n    coupon.dispose();\n    super.dispose();\n",
)

# There are two socialQuote calls; patch both by exact common block globally via direct text manipulation.
p = Path('lib/social/social_panel.dart')
text = p.read_text(encoding='utf-8')
old = "          parameters: currentParameters(),\n        );"
new = "          parameters: currentParameters(),\n          couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),\n        );"
if text.count(old) < 1:
    raise SystemExit('social quote call anchor missing')
text = text.replace(old, new)
old_create = "        parameters: currentParameters(),\n      );"
new_create = "        parameters: currentParameters(),\n        couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),\n      );"
# At this point create call has a unique anchor distinct from quote indentation.
if old_create not in text:
    raise SystemExit('create social order anchor missing')
text = text.replace(old_create, new_create, 1)
p.write_text(text, encoding='utf-8')

replace_once(
    'lib/social/social_panel.dart',
    "    if (error.code == 'cancel_not_supported') return t('لغو این سفارش از سمت Provider پشتیبانی نمی‌شود.', 'Provider does not support cancelling this order.');\n    return t('عملیات انجام نشد. دوباره تلاش کنید.', 'The operation failed. Please try again.');\n",
    "    if (error.code == 'cancel_not_supported') return t('لغو این سفارش از سمت Provider پشتیبانی نمی‌شود.', 'Provider does not support cancelling this order.');\n    if (error.code == 'coupon_invalid') return t('کد تخفیف معتبر نیست.', 'Coupon code is invalid.');\n    if (error.code == 'coupon_expired') return t('اعتبار این کد تخفیف تمام شده است.', 'This coupon has expired.');\n    if (error.code == 'coupon_not_started') return t('زمان استفاده از این کد هنوز شروع نشده است.', 'This coupon is not active yet.');\n    if (error.code == 'coupon_usage_limit') return t('سقف استفاده از این کد تکمیل شده است.', 'This coupon has reached its usage limit.');\n    if (error.code == 'coupon_min_order') return t('مبلغ سفارش برای این کد کافی نیست.', 'This order does not meet the coupon minimum.');\n    return t('عملیات انجام نشد. دوباره تلاش کنید.', 'The operation failed. Please try again.');\n",
)

replace_once(
    'lib/social/social_panel.dart',
    "          Container(\n            padding: const EdgeInsets.all(14),\n            decoration: BoxDecoration(color: const Color(0xFFF4FAFF), borderRadius: BorderRadius.circular(16)),\n            child: Column(\n              children: [\n                _InfoRow(label: t('نرخ', 'Rate'), value: '${host.money(service.priceRateAfn, showBase: true)} / ${service.priceUnit}'),\n                const SizedBox(height: 8),\n                _InfoRow(\n                  label: t('قیمت نهایی', 'Total'),\n                  value: quote == null ? t('پس از تکمیل فرم', 'Complete the form') : host.money(quote!.totalAmountAfn, showBase: true),\n                  strong: true,\n                ),\n              ],\n            ),\n          ),\n",
    "          TextField(\n            controller: coupon,\n            textCapitalization: TextCapitalization.characters,\n            decoration: InputDecoration(\n              labelText: t('کد تخفیف', 'Coupon code'),\n              hintText: t('اختیاری', 'Optional'),\n              prefixIcon: const Icon(Icons.local_offer_outlined),\n              suffixIcon: coupon.text.trim().isEmpty\n                  ? null\n                  : IconButton(onPressed: coupon.clear, icon: const Icon(Icons.close_rounded)),\n            ),\n          ),\n          const SizedBox(height: 12),\n          Container(\n            padding: const EdgeInsets.all(14),\n            decoration: BoxDecoration(color: const Color(0xFFF4FAFF), borderRadius: BorderRadius.circular(16)),\n            child: Column(\n              children: [\n                _InfoRow(label: t('نرخ', 'Rate'), value: '${host.money(service.priceRateAfn, showBase: true)} / ${service.priceUnit}'),\n                if (quote != null && quote!.discountAmountAfn > 0) ...[\n                  const SizedBox(height: 8),\n                  _InfoRow(label: t('جمع قبل از تخفیف', 'Subtotal'), value: host.money(quote!.subtotalAmountAfn, showBase: true)),\n                  const SizedBox(height: 8),\n                  _InfoRow(label: t('تخفیف', 'Discount'), value: '- ${host.money(quote!.discountAmountAfn, showBase: true)}'),\n                ],\n                const SizedBox(height: 8),\n                _InfoRow(\n                  label: t('قیمت نهایی', 'Total'),\n                  value: quote == null ? t('پس از تکمیل فرم', 'Complete the form') : host.money(quote!.totalAmountAfn, showBase: true),\n                  strong: true,\n                ),\n              ],\n            ),\n          ),\n",
)

print('Coupon checkout patch applied.')
