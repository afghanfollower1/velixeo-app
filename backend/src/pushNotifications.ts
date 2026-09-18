import {
  NotificationAudience,
  NotificationPriority,
  NotificationType,
  type Notification,
  type PrismaClient,
} from '@prisma/client';
import { GoogleAuth } from 'google-auth-library';

type FirebaseServiceAccount = {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};

function firebaseServiceAccount(): FirebaseServiceAccount | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as FirebaseServiceAccount;
    if (!parsed.client_email?.trim() || !parsed.private_key?.trim()) return null;
    return parsed;
  } catch {
    return null;
  }
}

function firebaseProjectId(account = firebaseServiceAccount()) {
  return process.env.FIREBASE_PROJECT_ID?.trim() || account?.project_id?.trim() || '';
}

export function firebasePushConfigured() {
  const account = firebaseServiceAccount();
  return Boolean(account && firebaseProjectId(account));
}

export function firebaseClientConfig() {
  const projectId = firebaseProjectId();
  const apiKey =
    process.env.FIREBASE_ANDROID_API_KEY?.trim()
    || process.env.FIREBASE_API_KEY?.trim()
    || process.env.FIREBASE_WEB_API_KEY?.trim()
    || '';
  const appId =
    process.env.FIREBASE_ANDROID_APP_ID?.trim()
    || process.env.FIREBASE_APP_ID?.trim()
    || '';
  const messagingSenderId = process.env.FIREBASE_MESSAGING_SENDER_ID?.trim() || '';
  const enabled = Boolean(
    projectId
      && apiKey
      && appId
      && messagingSenderId,
  );
  return {
    enabled,
    serverPushEnabled: firebasePushConfigured(),
    projectId: enabled ? projectId : null,
    apiKey: enabled ? apiKey : null,
    appId: enabled ? appId : null,
    messagingSenderId: enabled ? messagingSenderId : null,
  };
}

async function firebaseAccessToken() {
  const account = firebaseServiceAccount();
  const projectId = firebaseProjectId(account);
  if (!account || !projectId) throw new Error('firebase_push_not_configured');
  const auth = new GoogleAuth({
    credentials: {
      client_email: account.client_email,
      private_key: account.private_key,
      project_id: projectId,
    },
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const value = typeof token === 'string' ? token : token?.token;
  if (!value) throw new Error('firebase_access_token_failed');
  return { token: value, projectId };
}

type PushSummary = {
  configured: boolean;
  total: number;
  sent: number;
  failed: number;
  disabledTokens: number;
};

function notificationChannel(type: NotificationType) {
  switch (type) {
    case NotificationType.ORDER:
    case NotificationType.REFILL:
    case NotificationType.DRIPFEED:
      return 'velixeo_orders';
    case NotificationType.PAYMENT:
    case NotificationType.WALLET:
      return 'velixeo_wallet';
    case NotificationType.SUPPORT:
      return 'velixeo_support';
    case NotificationType.PROMOTION:
      return 'velixeo_promotions';
    default:
      return 'velixeo_system';
  }
}

function isUrgent(priority: NotificationPriority, type: NotificationType) {
  if (priority === NotificationPriority.HIGH) return true;
  return [
    NotificationType.ORDER,
    NotificationType.PAYMENT,
    NotificationType.WALLET,
    NotificationType.SUPPORT,
    NotificationType.ACCOUNT,
  ].includes(type);
}

export async function sendNotificationPush(
  prisma: PrismaClient,
  notification: Pick<Notification, 'id' | 'audience' | 'userId' | 'type' | 'priority' | 'titleFa' | 'titleEn' | 'bodyFa' | 'bodyEn' | 'actionRoute' | 'actionEntityId' | 'imageUrl'>,
): Promise<PushSummary> {
  if (!firebasePushConfigured()) {
    return { configured: false, total: 0, sent: 0, failed: 0, disabledTokens: 0 };
  }

  const devices = await prisma.pushDevice.findMany({
    where: {
      enabled: true,
      ...(notification.audience === NotificationAudience.USER && notification.userId
        ? { userId: notification.userId }
        : {}),
    },
    include: {
      user: { select: { locale: true } },
    },
    orderBy: { lastSeenAt: 'desc' },
    take: 5000,
  });
  if (devices.length === 0) {
    return { configured: true, total: 0, sent: 0, failed: 0, disabledTokens: 0 };
  }

  const { token: accessToken, projectId } = await firebaseAccessToken();
  let sent = 0;
  let failed = 0;
  let disabledTokens = 0;

  for (let offset = 0; offset < devices.length; offset += 50) {
    const batch = devices.slice(offset, offset + 50);
    const results = await Promise.all(batch.map(async (device) => {
      const useFa = String(device.user.locale) === 'FA';
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: {
                title: useFa ? notification.titleFa : notification.titleEn,
                body: useFa ? notification.bodyFa : notification.bodyEn,
                ...(notification.imageUrl ? { image: notification.imageUrl } : {}),
              },
              data: {
                kind: 'notification',
                notificationId: notification.id,
                type: notification.type,
                route: notification.actionRoute || 'notifications',
                entityId: notification.actionEntityId || '',
              },
              android: {
                priority: isUrgent(notification.priority, notification.type) ? 'high' : 'normal',
                ttl: '86400s',
                collapse_key: `velixeo-notification-${notification.id}`,
                notification: {
                  sound: notification.type === NotificationType.PROMOTION ? undefined : 'default',
                  channel_id: notificationChannel(notification.type),
                  tag: `velixeo-${notification.id}`,
                  notification_priority: isUrgent(notification.priority, notification.type)
                    ? 'PRIORITY_HIGH'
                    : 'PRIORITY_DEFAULT',
                  default_vibrate_timings: notification.type !== NotificationType.PROMOTION,
                  visibility: 'PUBLIC',
                },
              },
            },
          }),
        },
      );

      if (response.ok) return { sent: true, disable: false };
      let raw = '';
      try { raw = await response.text(); } catch {}
      const upper = raw.toUpperCase();
      const disable = upper.includes('UNREGISTERED') || upper.includes('INVALID_ARGUMENT');
      return { sent: false, disable };
    }));

    for (let index = 0; index < results.length; index += 1) {
      const result = results[index]!;
      if (result.sent) {
        sent += 1;
        continue;
      }
      failed += 1;
      if (result.disable) {
        disabledTokens += 1;
        await prisma.pushDevice.updateMany({
          where: { id: batch[index]!.id },
          data: { enabled: false },
        });
      }
    }
  }

  return {
    configured: true,
    total: devices.length,
    sent,
    failed,
    disabledTokens,
  };
}

export async function dispatchNotificationPush(
  prisma: PrismaClient,
  notification: Notification,
) {
  const push = await sendNotificationPush(prisma, notification);
  if (push.configured) {
    await prisma.notification.update({
      where: { id: notification.id },
      data: {
        pushTotal: push.total,
        pushSent: push.sent,
        pushFailed: push.failed,
        pushDisabledTokens: push.disabledTokens,
        lastPushAt: new Date(),
      },
    });
  }
  return push;
}

export async function dispatchDueNotificationPushes(
  prisma: PrismaClient,
  logger?: { error?: (value: unknown, message?: string) => void },
) {
  const now = new Date();
  const due = await prisma.notification.findMany({
    where: {
      enabled: true,
      publishAt: { lte: now },
      lastPushAt: null,
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    },
    orderBy: { publishAt: 'asc' },
    take: 60,
  });
  for (const notification of due) {
    try {
      await dispatchNotificationPush(prisma, notification);
    } catch (error) {
      logger?.error?.(error, 'scheduled notification push failed');
    }
  }
  return due.length;
}

export function startNotificationPushScheduler(
  prisma: PrismaClient,
  logger?: { error?: (value: unknown, message?: string) => void },
) {
  const run = () => void dispatchDueNotificationPushes(prisma, logger).catch((error) => {
    logger?.error?.(error, 'notification push scheduler failed');
  });
  run();
  const timer = setInterval(run, 60_000);
  timer.unref?.();
  return () => clearInterval(timer);
}
