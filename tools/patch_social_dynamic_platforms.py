from pathlib import Path

p = Path('lib/social/social_panel.dart')
s = p.read_text(encoding='utf-8')

replacements = [
    (
        "'INSTAGRAM','TIKTOK','YOUTUBE','FACEBOOK','TELEGRAM','X','THREADS',\n      'SNAPCHAT'",
        "'INSTAGRAM','TIKTOK','YOUTUBE','FACEBOOK','TELEGRAM','WHATSAPP','X','THREADS',\n      'SNAPCHAT'",
    ),
    (
        "case 'TELEGRAM': return Icons.send_rounded;\n      case 'FACEBOOK':",
        "case 'TELEGRAM': return Icons.send_rounded;\n      case 'WHATSAPP': return Icons.chat_rounded;\n      case 'FACEBOOK':",
    ),
    (
        "case 'TELEGRAM': return 'Telegram';\n      case 'X':",
        "case 'TELEGRAM': return 'Telegram';\n      case 'WHATSAPP': return 'WhatsApp';\n      case 'X':",
    ),
    (
        "case 'DISCORD': return 'Discord';\n      default: return fa ? 'سایر' : 'Other';",
        "case 'DISCORD': return 'Discord';\n      default:\n        final readable = platform\n            .split('_')\n            .where((part) => part.isNotEmpty)\n            .map((part) => part.length == 1\n                ? part.toUpperCase()\n                : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')\n            .join(' ');\n        return readable.isEmpty ? (fa ? 'سایر' : 'Other') : readable;",
    ),
]

changed = False
for old, new in replacements:
    if new in s:
        continue
    if old not in s:
        raise RuntimeError(f'Anchor not found: {old[:100]}')
    s = s.replace(old, new, 1)
    changed = True

if changed:
    p.write_text(s, encoding='utf-8')
    print('Dynamic social platform support applied.')
else:
    print('Dynamic social platform support already applied.')
