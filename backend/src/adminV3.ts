import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { PrismaClient } from '@prisma/client';
import { registerAdminV3 as registerFigmaAdminV3 } from './adminFigmaEnglish.js';
import { registerAdminSocialProviderManager } from './adminSocialProviderManager.js';
import { registerAdminLocale } from './adminLocale.js';

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};
type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;

export function registerAdminV3(
  app: FastifyInstance,
  prisma: PrismaClient,
  resolveAdmin: AdminResolver,
) {
  registerAdminLocale(app);
  registerAdminSocialProviderManager(app, prisma, resolveAdmin);
  registerFigmaAdminV3(app, prisma, resolveAdmin);
}
