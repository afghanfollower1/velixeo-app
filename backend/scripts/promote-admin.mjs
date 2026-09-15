import { PrismaClient, UserRole } from '@prisma/client';

const prisma = new PrismaClient();
const targetEmail = (process.env.TARGET_ADMIN_EMAIL || '').trim().toLowerCase();

if (!targetEmail) {
  console.log('ADMIN_PROMOTION_SKIPPED');
  await prisma.$disconnect();
  process.exit(0);
}

try {
  const users = await prisma.user.findMany({
    where: {
      email: {
        equals: targetEmail,
        mode: 'insensitive',
      },
    },
    select: { id: true, role: true },
  });

  if (users.length !== 1) {
    console.error(`ADMIN_PROMOTION_MATCH_COUNT=${users.length}`);
    await prisma.$disconnect();
    process.exit(2);
  }

  const user = users[0];
  if (user.role !== UserRole.ADMIN) {
    await prisma.user.update({
      where: { id: user.id },
      data: { role: UserRole.ADMIN },
    });
  }

  const verified = await prisma.user.findUnique({
    where: { id: user.id },
    select: { role: true },
  });

  if (verified?.role !== UserRole.ADMIN) {
    console.error('ADMIN_PROMOTION_VERIFY_FAILED');
    await prisma.$disconnect();
    process.exit(3);
  }

  console.log('ADMIN_PROMOTION_OK');
  await prisma.$disconnect();
} catch (error) {
  console.error('ADMIN_PROMOTION_FAILED', error instanceof Error ? error.message : 'unknown_error');
  await prisma.$disconnect();
  process.exit(1);
}
