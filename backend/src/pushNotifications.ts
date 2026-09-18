import {
  NotificationAudience,
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
  const apiKey = process.env.FIREBASE_WEB_API_KEY?.trim() || '';
  const appId = process.env.FIREBASE_APP_ID?.trim() || '';
  const messagingSenderId = process.env.FIREBASE_MESSAGING_SENDER_ID?.trim() || '';
  const enabled = Boolean(
    firebasePushConfigured()
      && projectId
      && apiKey
      && appId
      && messagingSenderId,
  );
  return {
    enabled,
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

export async function sendNotificationPush(
  prisma: PrismaClient,
  notification: Pick<Notification, 'id' | 'audience' | 'userId' | 'titleFa' | 'titleEn' | 'bodyFa' | 'bodyEn'>,
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
              },
              data: {
                type: 'notification',
                notificationId: notification.id,
              },
              android: {
                priority: 'high',
                notification: {
                  channel_id: 'velixeo_general',
                  sound: 'default',
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
