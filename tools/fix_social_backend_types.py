from pathlib import Path
p=Path('backend/src/socialRoutes.ts')
s=p.read_text()
s=s.replace("  if (![OrderStatus.PARTIAL, OrderStatus.CANCELLED, OrderStatus.FAILED].includes(status)) return null;", "  if (\n    status !== OrderStatus.PARTIAL &&\n    status !== OrderStatus.CANCELLED &&\n    status !== OrderStatus.FAILED\n  ) return null;")
s=s.replace("              providerResponse: result.raw,", "              providerResponse: result.raw as Prisma.InputJsonValue,")
s=s.replace("    if ([OrderStatus.COMPLETED, OrderStatus.CANCELLED, OrderStatus.REFUNDED, OrderStatus.FAILED].includes(order.status)) {", "    if (\n      order.status === OrderStatus.COMPLETED ||\n      order.status === OrderStatus.CANCELLED ||\n      order.status === OrderStatus.REFUNDED ||\n      order.status === OrderStatus.FAILED\n    ) {")
p.write_text(s)
