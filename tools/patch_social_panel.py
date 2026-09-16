from pathlib import Path
import runpy
import subprocess

# This existing trusted workflow is reused for the next validated completion pass.
runpy.run_path('tools/patch_coupon_checkout.py', run_name='__main__')

# Stage files that were added after the legacy workflow's original explicit list.
subprocess.run([
    'git', 'add',
    'backend/src/socialRoutes.ts',
    'lib/social/social_models.dart',
    'lib/social/social_panel.dart',
], check=True)

print('Coupon checkout integration applied and staged.')
