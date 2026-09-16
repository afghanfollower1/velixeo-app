from pathlib import Path

p = Path('lib/app.dart')
s = p.read_text(encoding='utf-8')
old = "Container(minWidth: 17, height: 17, padding: const EdgeInsets.symmetric(horizontal: 4),"
new = "Container(constraints: const BoxConstraints(minWidth: 17), height: 17, padding: const EdgeInsets.symmetric(horizontal: 4),"
if old in s:
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('Figma Flutter compatibility fix applied.')
