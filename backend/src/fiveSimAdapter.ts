import type { Provider } from '@prisma/client';
import { decryptProviderSecret } from './providerSecrets.js';

export type FiveSimPrice = {
  country: string;
  product: string;
  operator: string;
  cost: number;
  count: number;
  rate: number | null;
};

export type FiveSimSms = {
  createdAt?: string;
  date?: string;
  sender?: string;
  text?: string;
  code?: string;
};

export type FiveSimOrder = {
  id: string;
  phone: string;
  operator?: string;
  product: string;
  price: number;
  status: string;
  expires?: string;
  createdAt?: string;
  country?: string;
  sms: FiveSimSms[];
  raw: Record<string, unknown>;
};

export type FiveSimProfile = {
  balance: number;
  rating?: number;
  email?: string;
  raw: Record<string, unknown>;
};

export class FiveSimError extends Error {
  constructor(
    message: string,
    options: { statusCode?: number; providerMessage?: string; uncertain?: boolean } = {},
  ) {
    super(message);
    this.name = 'FiveSimError';
    this.statusCode = options.statusCode;
    this.providerMessage = options.providerMessage;
    this.uncertain = options.uncertain ?? false;
  }

  readonly statusCode?: number;
  readonly providerMessage?: string;
  readonly uncertain: boolean;
}

function objectValue(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function numberValue(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function deliveryPercentValue(value: unknown): number | null {
  if (value == null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return null;
  // 5SIM price feeds can expose the SMS success rate either as a fraction
  // (0.0441) or as a human percentage (4.41). Normalize both to 0..100.
  const percent = parsed > 0 && parsed <= 1 ? parsed * 100 : parsed;
  return Math.max(0, Math.min(100, percent));
}

function stringField(row: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = row[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return '';
}

function apiToken(secret: string) {
  const trimmed = secret.trim();
  if (!trimmed) throw new Error('FIVESIM_SECRET_EMPTY');
  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>;
    const token = parsed.token ?? parsed.apiToken ?? parsed.api_token ?? parsed.apiKey ?? parsed.api_key ?? parsed.key;
    if (typeof token === 'string' && token.trim()) return token.trim();
  } catch {
    // Plain bearer tokens are supported too.
  }
  return trimmed;
}

function orderFromJson(value: unknown): FiveSimOrder {
  const row = objectValue(value);
  const id = row.id;
  const product = row.product;
  const phone = row.phone;
  if (id == null || product == null || phone == null) {
    throw new FiveSimError('fivesim_invalid_order_response', {
      providerMessage: JSON.stringify(row).slice(0, 300),
    });
  }
  const sms = Array.isArray(row.sms)
    ? row.sms.map((item) => {
        const itemRow = objectValue(item);
        return {
          createdAt: itemRow.created_at == null ? undefined : String(itemRow.created_at),
          date: itemRow.date == null ? undefined : String(itemRow.date),
          sender: itemRow.sender == null ? undefined : String(itemRow.sender),
          text: itemRow.text == null ? undefined : String(itemRow.text),
          code: itemRow.code == null ? undefined : String(itemRow.code),
        } satisfies FiveSimSms;
      })
    : [];
  return {
    id: String(id),
    phone: String(phone),
    operator: row.operator == null ? undefined : String(row.operator),
    product: String(product),
    price: numberValue(row.price),
    status: String(row.status ?? 'PENDING').toUpperCase(),
    expires: row.expires == null ? undefined : String(row.expires),
    createdAt: row.created_at == null ? undefined : String(row.created_at),
    country: row.country == null ? undefined : String(row.country),
    sms,
    raw: row,
  };
}

export class FiveSimClient {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
    private readonly timeoutMs: number,
  ) {}

  private async get(
    path: string,
    options: { auth?: boolean; uncertainOnNetworkFailure?: boolean } = {},
  ): Promise<unknown> {
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}${path}`, {
        method: 'GET',
        headers: {
          Accept: 'application/json',
          ...(options.auth === false ? {} : { Authorization: `Bearer ${this.token}` }),
        },
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (error) {
      throw new FiveSimError('fivesim_unreachable', {
        uncertain: options.uncertainOnNetworkFailure === true,
        providerMessage: error instanceof Error ? error.message : undefined,
      });
    }

    const text = await response.text();
    let parsed: unknown = text;
    if (text.trim()) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = text;
      }
    }

    if (!response.ok) {
      const message = typeof parsed === 'string'
        ? parsed
        : JSON.stringify(parsed).slice(0, 300);
      throw new FiveSimError('fivesim_request_failed', {
        statusCode: response.status,
        providerMessage: message,
        uncertain: options.uncertainOnNetworkFailure === true && response.status >= 500,
      });
    }
    return parsed;
  }

  async profile(): Promise<FiveSimProfile> {
    const raw = objectValue(await this.get('/v1/user/profile'));
    return {
      balance: numberValue(raw.balance),
      rating: raw.rating == null ? undefined : numberValue(raw.rating),
      email: raw.email == null ? undefined : String(raw.email),
      raw,
    };
  }

  async countries() {
    const raw = await this.get('/v1/guest/countries', { auth: false });
    return objectValue(raw);
  }

  async prices(filters: { country?: string; product?: string } = {}): Promise<FiveSimPrice[]> {
    const query = new URLSearchParams();
    if (filters.country) query.set('country', filters.country);
    if (filters.product) query.set('product', filters.product);
    const suffix = query.size ? `?${query}` : '';
    const raw = await this.get(`/v1/guest/prices${suffix}`, { auth: false });
    const rows: FiveSimPrice[] = [];

    // 5SIM has used several equivalent shapes for the guest price feed.
    // Walk both objects and arrays, and prefer explicit leaf fields when present.
    const walk = (node: unknown, path: string[]) => {
      if (Array.isArray(node)) {
        for (const item of node) walk(item, path);
        return;
      }
      const obj = objectValue(node);
      if ('cost' in obj && 'count' in obj) {
        const labels = [...path].filter(Boolean);
        let country = stringField(obj, ['country', 'country_name', 'countryName']) || filters.country || '';
        let product = stringField(obj, ['product', 'service', 'service_name', 'serviceName']) || filters.product || '';
        let operator = stringField(obj, ['operator', 'operator_name', 'operatorName']);

        if (!operator) {
          if (filters.country && filters.product) {
            operator = labels.at(-1) ?? '';
          } else if (filters.country) {
            product ||= labels.at(-2) ?? labels.at(0) ?? '';
            operator = labels.at(-1) ?? '';
          } else if (filters.product) {
            country ||= labels.at(-2) ?? labels.at(0) ?? '';
            operator = labels.at(-1) ?? '';
          } else {
            country ||= labels.at(-3) ?? '';
            product ||= labels.at(-2) ?? '';
            operator = labels.at(-1) ?? '';
          }
        }

        if (country && product && operator) {
          rows.push({
            country,
            product,
            operator,
            cost: numberValue(obj.cost),
            count: Math.max(0, Math.trunc(numberValue(obj.count))),
            rate: deliveryPercentValue(obj.rate ?? obj.delivery_rate ?? obj.deliveryRate ?? obj.success_rate ?? obj.successRate),
          });
        }
        return;
      }
      for (const [key, value] of Object.entries(obj)) {
        walk(value, [...path, key]);
      }
    };
    walk(raw, []);

    // A provider response can repeat the same operator through aliases/nesting.
    // Keep exactly one customer-visible row per country/service/operator.
    const unique = new Map<string, FiveSimPrice>();
    for (const row of rows) {
      const key = `${row.country.toLowerCase()}|${row.product.toLowerCase()}|${row.operator.toLowerCase()}`;
      const previous = unique.get(key);
      if (!previous) {
        unique.set(key, row);
        continue;
      }
      unique.set(key, {
        ...previous,
        cost: Math.min(previous.cost, row.cost),
        count: Math.max(previous.count, row.count),
        rate: previous.rate == null
          ? row.rate
          : row.rate == null
              ? previous.rate
              : Math.max(previous.rate, row.rate),
      });
    }
    return [...unique.values()];
  }

  async buyActivation(input: {
    country: string;
    operator: string;
    product: string;
  }): Promise<FiveSimOrder> {
    const path = `/v1/user/buy/activation/${encodeURIComponent(input.country)}/${encodeURIComponent(input.operator)}/${encodeURIComponent(input.product)}`;
    return orderFromJson(await this.get(path, { uncertainOnNetworkFailure: true }));
  }

  async check(orderId: string) {
    return orderFromJson(await this.get(`/v1/user/check/${encodeURIComponent(orderId)}`));
  }

  async finish(orderId: string) {
    return orderFromJson(await this.get(`/v1/user/finish/${encodeURIComponent(orderId)}`));
  }

  async cancel(orderId: string) {
    return orderFromJson(await this.get(`/v1/user/cancel/${encodeURIComponent(orderId)}`, {
      uncertainOnNetworkFailure: true,
    }));
  }
}

export function fiveSimClientForProvider(provider: Provider) {
  if (provider.kind !== 'VIRTUAL_NUMBER') throw new Error('PROVIDER_NOT_VIRTUAL_NUMBER');
  const secret = decryptProviderSecret(provider);
  if (!secret) throw new Error('VIRTUAL_NUMBER_PROVIDER_SECRET_MISSING');
  const baseUrl = (provider.baseUrl?.trim() || 'https://5sim.net').replace(/\/$/, '');
  return new FiveSimClient(
    baseUrl,
    apiToken(secret),
    Math.min(180_000, Math.max(5_000, provider.timeoutSeconds * 1000)),
  );
}
