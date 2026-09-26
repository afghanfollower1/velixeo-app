import type { Provider } from '@prisma/client';
import { decryptProviderSecret } from './providerSecrets.js';
import { parseEtaMinutes } from './socialEta.js';

export type ProviderWebAverage = {
  text: string;
  minMinutes: number | null;
  maxMinutes: number | null;
};

type ProviderWebCredentials = {
  username: string;
  password: string;
};

function secretObject(provider: Provider) {
  const raw = decryptProviderSecret(provider);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

export function providerWebCredentials(provider: Provider): ProviderWebCredentials | null {
  const row = secretObject(provider);
  if (!row) return null;
  const username = String(
    row.panelUsername
      ?? row.panel_username
      ?? row.webUsername
      ?? row.web_username
      ?? row.username
      ?? '',
  ).trim();
  const password = String(
    row.panelPassword
      ?? row.panel_password
      ?? row.webPassword
      ?? row.web_password
      ?? row.password
      ?? '',
  );
  return username && password ? { username, password } : null;
}

function providerOrigin(provider: Provider) {
  if (!provider.baseUrl) return null;
  try {
    return new URL(provider.baseUrl).origin;
  } catch {
    return null;
  }
}

function htmlDecode(value: string) {
  const named: Record<string, string> = {
    amp: '&',
    lt: '<',
    gt: '>',
    quot: '"',
    apos: "'",
    nbsp: ' ',
  };
  return value
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code: string) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&([a-z]+);/gi, (all, name: string) => named[name.toLowerCase()] ?? all);
}

function textOnly(html: string) {
  return htmlDecode(
    html
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim(),
  );
}

function attrs(tag: string) {
  const out = new Map<string, string>();
  const re = /([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+)))?/g;
  for (const match of tag.matchAll(re)) {
    out.set(match[1].toLowerCase(), htmlDecode(match[2] ?? match[3] ?? match[4] ?? ''));
  }
  return out;
}

function cookiePairs(response: Response) {
  const headers = response.headers as Headers & { getSetCookie?: () => string[] };
  const raw = typeof headers.getSetCookie === 'function'
    ? headers.getSetCookie()
    : [response.headers.get('set-cookie')].filter((item): item is string => Boolean(item));
  return raw.map(item => item.split(';', 1)[0]).filter(Boolean);
}

function mergeCookies(current: Map<string, string>, pairs: string[]) {
  for (const pair of pairs) {
    const idx = pair.indexOf('=');
    if (idx <= 0) continue;
    current.set(pair.slice(0, idx).trim(), pair.slice(idx + 1).trim());
  }
}

function cookieHeader(cookies: Map<string, string>) {
  return [...cookies.entries()].map(([key, value]) => `${key}=${value}`).join('; ');
}

function loginForm(html: string, baseUrl: URL) {
  const forms = [...html.matchAll(/<form\b([^>]*)>([\s\S]*?)<\/form>/gi)];
  for (const match of forms) {
    const body = match[2] ?? '';
    if (!/<input\b[^>]*type\s*=\s*["']?password/i.test(body)) continue;
    const formAttrs = attrs(match[1] ?? '');
    const actionRaw = formAttrs.get('action') || baseUrl.pathname || '/';
    const action = new URL(actionRaw, baseUrl);
    const fields = new URLSearchParams();
    let usernameField = '';
    let passwordField = '';

    for (const input of body.matchAll(/<input\b([^>]*)>/gi)) {
      const inputAttrs = attrs(input[1] ?? '');
      const name = inputAttrs.get('name') || '';
      if (!name) continue;
      const type = (inputAttrs.get('type') || 'text').toLowerCase();
      const value = inputAttrs.get('value') || '';
      if (type === 'password') {
        passwordField ||= name;
        continue;
      }
      if (
        !usernameField
        && ['text', 'email', 'tel'].includes(type)
        && /user|login|email/i.test(name)
      ) {
        usernameField = name;
        continue;
      }
      if (type === 'hidden') fields.set(name, value);
      if (type === 'checkbox' && inputAttrs.has('checked')) fields.set(name, value || '1');
    }

    if (!usernameField || !passwordField) continue;
    return { action, fields, usernameField, passwordField };
  }
  return null;
}

async function fetchWithCookies(
  url: URL,
  cookies: Map<string, string>,
  init: RequestInit = {},
) {
  const headers = new Headers(init.headers);
  headers.set('Accept', 'text/html,application/xhtml+xml');
  headers.set(
    'User-Agent',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36 VELIXEO/1.0',
  );
  const cookie = cookieHeader(cookies);
  if (cookie) headers.set('Cookie', cookie);
  const response = await fetch(url, {
    ...init,
    headers,
    redirect: 'manual',
    signal: AbortSignal.timeout(30_000),
  });
  mergeCookies(cookies, cookiePairs(response));
  return response;
}

async function follow(
  response: Response,
  cookies: Map<string, string>,
  fallbackUrl: URL,
) {
  let current = response;
  let url = fallbackUrl;
  for (let hop = 0; hop < 5 && current.status >= 300 && current.status < 400; hop += 1) {
    const location = current.headers.get('location');
    if (!location) break;
    url = new URL(location, url);
    current = await fetchWithCookies(url, cookies);
  }
  return { response: current, url };
}

function parseServicesAverageTable(html: string) {
  const map = new Map<string, ProviderWebAverage>();
  for (const rowMatch of html.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const row = rowMatch[1] ?? '';
    const idMatch = row.match(/data-filter-table-service-id\s*=\s*["']?([^"'\s>]+)/i);
    if (!idMatch) continue;
    const serviceId = htmlDecode(idMatch[1] ?? '').trim();
    if (!serviceId) continue;

    const cells = [...row.matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(match => textOnly(match[1] ?? ''));
    if (cells.length < 6) continue;

    const averageText = (cells[5] ?? '').trim();
    if (!averageText || /not enough data|n\/a|unknown|^[-—]$/i.test(averageText)) continue;
    const parsed = parseEtaMinutes(averageText);
    map.set(serviceId, {
      text: averageText,
      minMinutes: parsed.minMinutes,
      maxMinutes: parsed.maxMinutes,
    });
  }
  return map;
}

export async function fetchProviderWebAverageTimes(provider: Provider) {
  const credentials = providerWebCredentials(provider);
  const origin = providerOrigin(provider);
  if (!credentials || !origin) return null;

  const cookies = new Map<string, string>();
  const rootUrl = new URL('/', origin);
  const root = await fetchWithCookies(rootUrl, cookies);
  const rootFollowed = await follow(root, cookies, rootUrl);
  const rootHtml = await rootFollowed.response.text();
  const form = loginForm(rootHtml, rootFollowed.url);
  if (!form) throw new Error('PROVIDER_WEB_LOGIN_FORM_NOT_FOUND');

  form.fields.set(form.usernameField, credentials.username);
  form.fields.set(form.passwordField, credentials.password);
  if (!form.fields.has('LoginForm[remember]')) form.fields.set('LoginForm[remember]', '1');

  const loginResponse = await fetchWithCookies(form.action, cookies, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Referer: rootFollowed.url.toString(),
    },
    body: form.fields,
  });
  const afterLogin = await follow(loginResponse, cookies, form.action);
  const afterLoginHtml = await afterLogin.response.text();

  if (
    /type\s*=\s*["']?password/i.test(afterLoginHtml)
    && /sign\s*in|login/i.test(textOnly(afterLoginHtml).slice(0, 1500))
  ) {
    throw new Error('PROVIDER_WEB_LOGIN_FAILED');
  }

  const servicesUrl = new URL('/services', origin);
  const servicesResponse = await fetchWithCookies(servicesUrl, cookies, {
    headers: { Referer: afterLogin.url.toString() },
  });
  const followed = await follow(servicesResponse, cookies, servicesUrl);
  const servicesHtml = await followed.response.text();

  if (!/data-filter-table-service-id/i.test(servicesHtml)) {
    throw new Error('PROVIDER_WEB_SERVICES_TABLE_NOT_FOUND');
  }

  return parseServicesAverageTable(servicesHtml);
}
