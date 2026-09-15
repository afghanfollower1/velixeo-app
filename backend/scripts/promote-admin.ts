import 'dotenv/config';
import { PrismaClient, UserRole } from '@prisma/client';

const prisma = new PrismaClient();
const identifier = process.argv[2]?.trim();

if (!identifier) {
  console.error('Usage: npm run admin:promote -- <email-or-phone>');
  process.exit(1);
}

try {
  const user = await prisma.user.findFirst({
    where: {
      OR: [
        { email: identifier.toLowerCase() },
        { phone: identifier.replace(/\s+/g, '') },
      ],
    },
  });

  if (!user) {
    console.error('User not found');
    process.exit(2);
  }

  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { role: UserRole.ADMIN },
  });

  console.log(`Admin enabled for user ${updated.id}`);
} finally {
  await prisma.$disconnect();
}
