import type { Provider } from '@prisma/client';
import { decryptProviderSecret } from './providerSecrets.js';

export type SmmService = {
  service: string;
  name: string;
  type: string;
  category: string;
  rate: string;
  min: number;
  max: number;
  refill: boolean;
  cancel: boolean;
  raw: Record<string, unknown>;
};

export type SmmBalance = {
  balance: string;
  currency: string;
};

export type SmmOrderStatus = {
  charge?: string;
  startCount?: string;
  status: string;
  remains?: string;
  currency?: string;
  raw: Record<string, unknown>;
};

export class SmmProviderError extends Error {
  constructor(
    message: string,
    options: { uncertain?: boolean; providerMessage?: string } = {},
  ) {
    super(message);
    this.name = 'SmmProviderError';
    this.uncertain = options.uncertain ?? false;
    this.providerMessage = options.providerMessage;
  }

  readonly uncertain: boolean;
  readonly providerMessage?: string;
}

function secretApiKey(secret: string) {
  const trimmed = secret.trim();
  if (!trimmed) throw new Error('SMM_PROVIDER_SECRET_EMPTY');
  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>;
    const key = parsed.apiKey ?? parsed.api_key ?? parsed.key ?? parsed.token;
    if (typeof key === 'string' && key.trim()) return key.trim();
  } catch {
    // Plain API keys are supported too.
  }
  return trimmed;
}

function asObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function boolValue(value: unknown) {
  return value === true || value === 1 || value === '1' || value === 'true';
}

function intValue(value: unknown) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

export class SmmPanelClient {
  constructor(
    private readonly apiUrl: string,
    private readonly apiKey: string,
    private readonly timeoutMs: number,
  ) {}

  private async post(
    fields: Record<string, string | number>,
    options: { uncertainOnNetworkFailure?: boolean } = {},
  ): Promise<unknown> {
    const body = new URLSearchParams();
    body.set('key', this.apiKey);
    for (const [key, value] of Object.entries(fields)) {
      body.set(key, String(value));
    }

    let response: Response;
    try {
      response = await fetch(this.apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body,
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (error) {
      throw new SmmProviderError('smm_provider_unreachable', {
        uncertain: options.uncertainOnNetworkFailure === true,
        providerMessage: error instanceof Error ? error.message : undefined,
      });
    }

    const text = await response.text();
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new SmmProviderError('smm_provider_invalid_json', {
        uncertain: options.uncertainOnNetworkFailure === true,
        providerMessage: text.slice(0, 240),
      });
    }

    if (!response.ok) {
      throw new SmmProviderError('smm_provider_http_error', {
        uncertain: options.uncertainOnNetworkFailure === true,
        providerMessage: `HTTP ${response.status}`,
      });
    }
    return parsed;
  }

  async services(): Promise<SmmService[]> {
    const raw = await this.post({ action: 'services' });
    if (!Array.isArray(raw)) {
      const error = asObject(raw).error;
      throw new SmmProviderError('smm_services_failed', {
        providerMessage: typeof error === 'string' ? error : undefined,
      });
    }
    return raw.flatMap((item) => {
      const row = asObject(item);
      const id = row.service;
      if (id == null) return [];
      return [{
        service: String(id),
        name: String(row.name ?? `Service ${id}`),
        type: String(row.type ?? 'Default'),
        category: String(row.category ?? 'Uncategorized'),
        rate: String(row.rate ?? '0'),
        min: intValue(row.min),
        max: intValue(row.max),
        refill: boolValue(row.refill),
        cancel: boolValue(row.cancel),
        raw: row,
      }];
    });
  }

  async balance(): Promise<SmmBalance> {
    const raw = asObject(await this.post({ action: 'balance' }));
    if (typeof raw.error === 'string') {
      throw new SmmProviderError('smm_balance_failed', { providerMessage: raw.error });
    }
    return {
      balance: String(raw.balance ?? '0'),
      currency: String(raw.currency ?? 'USD').toUpperCase(),
    };
  }

  async addOrder(fields: Record<string, string | number>) {
    const raw = asObject(await this.post(
      { action: 'add', ...fields },
      { uncertainOnNetworkFailure: true },
    ));
    if (typeof raw.error === 'string') {
      throw new SmmProviderError('smm_order_rejected', { providerMessage: raw.error });
    }
    const order = raw.order;
    if (order == null || String(order).trim() === '') {
      throw new SmmProviderError('smm_order_invalid_response', {
        uncertain: true,
        providerMessage: JSON.stringify(raw).slice(0, 240),
      });
    }
    return { orderId: String(order), raw };
  }

  async status(orderId: string): Promise<SmmOrderStatus> {
    const raw = asObject(await this.post({ action: 'status', order: orderId }));
    if (typeof raw.error === 'string') {
      throw new SmmProviderError('smm_status_failed', { providerMessage: raw.error });
    }
    return {
      charge: raw.charge == null ? undefined : String(raw.charge),
      startCount: raw.start_count == null ? undefined : String(raw.start_count),
      status: String(raw.status ?? 'Pending'),
      remains: raw.remains == null ? undefined : String(raw.remains),
      currency: raw.currency == null ? undefined : String(raw.currency).toUpperCase(),
      raw,
    };
  }

  async refill(orderId: string) {
    const raw = asObject(await this.post({ action: 'refill', order: orderId }));
    if (typeof raw.error === 'string') {
      throw new SmmProviderError('smm_refill_failed', { providerMessage: raw.error });
    }
    const refill = raw.refill;
    if (refill == null || typeof refill === 'object') {
      throw new SmmProviderError('smm_refill_failed', {
        providerMessage: JSON.stringify(refill ?? raw).slice(0, 240),
      });
    }
    return { refillId: String(refill), raw };
  }

  async refillStatus(refillId: string) {
    const raw = asObject(await this.post({ action: 'refill_status', refill: refillId }));
    if (typeof raw.error === 'string') {
      throw new SmmProviderError('smm_refill_status_failed', { providerMessage: raw.error });
    }
    return { status: String(raw.status ?? 'Pending'), raw };
  }

  async cancel(orderId: string) {
    const raw = await this.post({ action: 'cancel', orders: orderId });
    if (!Array.isArray(raw) || raw.length === 0) {
      throw new SmmProviderError('smm_cancel_failed', {
        providerMessage: JSON.stringify(raw).slice(0, 240),
      });
    }
    const item = asObject(raw[0]);
    const cancel = item.cancel;
    if (cancel && typeof cancel === 'object') {
      const error = asObject(cancel).error;
      throw new SmmProviderError('smm_cancel_failed', {
        providerMessage: typeof error === 'string' ? error : JSON.stringify(cancel).slice(0, 240),
      });
    }
    if (cancel !== 1 && cancel !== '1' && cancel !== true) {
      throw new SmmProviderError('smm_cancel_failed', {
        providerMessage: JSON.stringify(item).slice(0, 240),
      });
    }
    return { accepted: true, raw: item };
  }
}

export function smmClientForProvider(provider: Provider) {
  if (provider.kind !== 'SOCIAL') throw new Error('PROVIDER_NOT_SOCIAL');
  if (!provider.baseUrl?.trim()) throw new Error('SMM_PROVIDER_BASE_URL_MISSING');
  const secret = decryptProviderSecret(provider);
  if (!secret) throw new Error('SMM_PROVIDER_SECRET_MISSING');
  return new SmmPanelClient(
    provider.baseUrl.trim().replace(/\/$/, ''),
    secretApiKey(secret),
    Math.min(180_000, Math.max(5_000, provider.timeoutSeconds * 1000)),
  );
}
