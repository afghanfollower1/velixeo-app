from pathlib import Path

path = Path('backend/src/adminExtended.ts')
source = path.read_text()

source = source.replace(
    "<th>External ID</th><th>زمان</th>",
    "<th>External ID</th><th>تأیید Backend</th><th>زمان</th>",
    1,
)
source = source.replace(
    "${esc(p.provider?.name || '—')}",
    "${esc(p.gateway || p.provider?.name || '—')}",
    1,
)
old = "<td class=\"code\">${esc(p.externalId || p.referenceId || '—')}</td><td>${faDate(p.createdAt)}</td>"
new = "<td class=\"code\">${esc(p.externalId || p.referenceId || '—')}</td><td>${p.verifiedAt ? `<span class=\"badge okbadge\">Verified</span><br><span class=\"muted\">${faDate(p.verifiedAt)}</span>` : '<span class=\"badge\">Not verified</span>'}${p.failureReason ? `<br><span class=\"muted\">${esc(p.failureReason)}</span>` : ''}</td><td>${faDate(p.createdAt)}</td>"
if old not in source:
    raise SystemExit('payment row anchor not found')
source = source.replace(old, new, 1)
source = source.replace(
    '<tr><td colspan=\"7\" class=\"muted\">هنوز تراکنش پرداختی ثبت نشده است.</td></tr>',
    '<tr><td colspan=\"8\" class=\"muted\">هنوز تراکنش پرداختی ثبت نشده است.</td></tr>',
    1,
)

path.write_text(source)
