from pathlib import Path

backend=Path('backend/src/socialRoutes.ts')
s=backend.read_text()
s=s.replace("  if (type === 'package' || type.includes('subscription')) return 1;", "  if (type === 'package') return 1;")
s=s.replace(
"      order.status === OrderStatus.COMPLETED ||\n      order.status === OrderStatus.CANCELLED ||",
"      order.status === OrderStatus.COMPLETED ||\n      order.status === OrderStatus.PARTIAL ||\n      order.status === OrderStatus.CANCELLED ||",
1,
)
backend.write_text(s)

flutter=Path('lib/social/social_panel.dart')
f=flutter.read_text()
f=f.replace("  bool get terminal => ['COMPLETED','CANCELLED','FAILED','REFUNDED'].contains(order.status);", "  bool get terminal => ['COMPLETED','PARTIAL','CANCELLED','FAILED','REFUNDED'].contains(order.status);")
flutter.write_text(f)
