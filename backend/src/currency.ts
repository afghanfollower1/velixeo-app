export function normalizeCurrencyCode(
  value: string | null | undefined,
  fallback: string | null = 'USD',
): string | null {
  const raw = String(value ?? '').trim().toUpperCase().replace(/\s+/g, '');
  if (!raw || raw === 'AUTO') {
    if (fallback == null) return null;
    return normalizeCurrencyCode(fallback, null);
  }

  const aliases: Record<string, string> = {
    AFS: 'AFN',
    AFGHANI: 'AFN',
    IRT: 'TOMAN',
    TMN: 'TOMAN',
    TOM: 'TOMAN',
    USDT: 'USD',
  };
  const normalized = aliases[raw] ?? raw;
  if (!/^[A-Z0-9_-]{2,12}$/.test(normalized)) {
    throw new Error('INVALID_CURRENCY_CODE');
  }
  return normalized;
}
