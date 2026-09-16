from pathlib import Path
import runpy
import subprocess

# Reuse the validated completion patcher. This workflow is kept as the existing
# trusted contents-write path for large Flutter/backend integration updates.
runpy.run_path('tools/complete_live_panels.py', run_name='__main__')

# The legacy workflow's explicit git-add list predates the virtual-number module.
# Stage its small CI type fix here so it is committed together with the integration.
subprocess.run(['git', 'add', 'backend/src/virtualNumberRoutes.ts'], check=True)

print('Live panels patch applied and virtual-number route fix staged.')
