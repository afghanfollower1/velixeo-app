from pathlib import Path

path = Path('backend/src/adminExtended.ts')
source = path.read_text()

# Import WalletEntryStatus for an explicit completed-purchase invariant.
old_import = "  UserStatus,\n  WalletEntryType,\n} from '@prisma/client';"
new_import = "  UserStatus,\n  WalletEntryStatus,\n  WalletEntryType,\n} from '@prisma/client';"
if old_import in source:
    source = source.replace(old_import, new_import, 1)

message_anchor = "    already_refunded: ['این سفارش قبلاً Refund شده است.', true],\n"
message_line = "    refund_not_charged: ['برای این سفارش هیچ Ledger Purchase معتبر پیدا نشد؛ Refund مالی متوقف شد.', true],\n"
if message_line not in source:
    if message_anchor not in source:
        raise SystemExit('message anchor not found')
    source = source.replace(message_anchor, message_anchor + message_line, 1)

wallet_anchor = """          const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');
          const nextBalance = wallet.balanceAfn + order.totalAmountAfn;
"""
wallet_replacement = """          const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');

          // A refund must reverse a real, completed wallet purchase for this exact order.
          // This prevents an admin-created or malformed order from minting wallet balance.
          const purchaseEntry = await tx.walletEntry.findFirst({
            where: {
              walletId: wallet.id,
              type: WalletEntryType.PURCHASE,
              status: WalletEntryStatus.COMPLETED,
              referenceType: 'ORDER_PURCHASE',
              referenceId: order.id,
              amountAfn: -order.totalAmountAfn,
            },
            orderBy: { createdAt: 'desc' },
          });
          if (!purchaseEntry) throw new Error('ORDER_NOT_CHARGED');

          const nextBalance = wallet.balanceAfn + order.totalAmountAfn;
"""
if "throw new Error('ORDER_NOT_CHARGED')" not in source:
    if wallet_anchor not in source:
        raise SystemExit('wallet refund anchor not found')
    source = source.replace(wallet_anchor, wallet_replacement, 1)

metadata_old = "        { walletEntryId: refund.entry.id, userId: refund.order.userId },\n"
metadata_new = "        { walletEntryId: refund.entry.id, userId: refund.order.userId, invariant: 'ORDER_PURCHASE_LEDGER_REQUIRED' },\n"
if metadata_old in source:
    source = source.replace(metadata_old, metadata_new, 1)

catch_anchor = """      if (error instanceof Error && error.message === 'ORDER_NOT_FOUND') {
        return reply.code(303).redirect('/admin/orders?msg=not_found');
      }
      throw error;
"""
catch_replacement = """      if (error instanceof Error && error.message === 'ORDER_NOT_FOUND') {
        return reply.code(303).redirect('/admin/orders?msg=not_found');
      }
      if (error instanceof Error && error.message === 'ORDER_NOT_CHARGED') {
        return reply.code(303).redirect('/admin/orders?msg=refund_not_charged');
      }
      throw error;
"""
if "error.message === 'ORDER_NOT_CHARGED'" not in source:
    if catch_anchor not in source:
        raise SystemExit('refund catch anchor not found')
    source = source.replace(catch_anchor, catch_replacement, 1)

path.write_text(source)
