import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

const unsafeMethods = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function firstHeaderValue(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw?.split(',')[0]?.trim() || '';
}

function expectedHost(request: FastifyRequest) {
  return (
    firstHeaderValue(request.headers['x-forwarded-host']) ||
    firstHeaderValue(request.headers.host)
  ).toLowerCase();
}

function hostFromUrl(value: string | undefined) {
  if (!value) return '';
  try {
    return new URL(value).host.toLowerCase();
  } catch {
    return '';
  }
}

function deny(reply: FastifyReply) {
  return reply
    .code(403)
    .type('text/plain; charset=utf-8')
    .send('admin_request_origin_rejected');
}

/**
 * Protects the cookie-authenticated server-rendered admin console from CSRF.
 *
 * Admin API endpoints under /api/v1/admin use bearer JWT authentication and are
 * deliberately outside this guard. Browser form mutations under /admin rely on
 * a Strict SameSite cookie plus this explicit same-origin / Fetch-Metadata check.
 */
export function registerAdminCsrfGuard(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    if (!unsafeMethods.has(request.method.toUpperCase())) return;
    if (!request.url.startsWith('/admin')) return;

    const fetchSite = firstHeaderValue(request.headers['sec-fetch-site']).toLowerCase();
    if (fetchSite === 'cross-site') return deny(reply);

    const expected = expectedHost(request);
    if (!expected) return deny(reply);

    const origin = firstHeaderValue(request.headers.origin);
    if (origin) {
      if (hostFromUrl(origin) !== expected) return deny(reply);
      return;
    }

    const referer = firstHeaderValue(request.headers.referer);
    if (referer) {
      if (hostFromUrl(referer) !== expected) return deny(reply);
      return;
    }

    // Modern browsers send Sec-Fetch-Site on navigational form submissions.
    // Allow explicit same-origin / same-site browser requests when Origin and
    // Referer were stripped by a privacy layer, but reject ambiguous requests.
    if (fetchSite === 'same-origin' || fetchSite === 'same-site') return;

    return deny(reply);
  });
}
