#!/usr/bin/env bash
set -euo pipefail

required=(
  ANDROID_KEYSTORE_BASE64
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS
  ANDROID_KEY_PASSWORD
  FIREBASE_PROJECT_ID
  FIREBASE_ANDROID_API_KEY
  FIREBASE_ANDROID_APP_ID
  FIREBASE_MESSAGING_SENDER_ID
)
for name in "${required[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "::error::$name is required for deterministic Shorebird Android release/patch builds."
    exit 1
  fi
done

if [ "${ANDROID_KEY_ALIAS}" != "velixeo" ]; then
  echo "::error::ANDROID_KEY_ALIAS must be velixeo."
  exit 1
fi

printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/velixeo-release.jks
cat > android/key.properties <<EOF
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=velixeo-release.jks
EOF

python3 -m pip install --quiet pillow cairosvg
python3 - <<'PY'
from pathlib import Path
import io
from PIL import Image
import cairosvg

source = Path("assets/brand/velixeo-app-icon.svg")
if not source.exists():
    raise SystemExit("VELIXEO brand icon source is missing")
master = cairosvg.svg2png(bytestring=source.read_bytes(), output_width=1024, output_height=1024)
image = Image.open(io.BytesIO(master)).convert("RGBA")
for folder, size in {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}.items():
    out = Path("android/app/src/main/res") / folder
    out.mkdir(parents=True, exist_ok=True)
    icon = image.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(out / "ic_launcher.png", optimize=True)
    icon.save(out / "ic_launcher_round.png", optimize=True)
PY

python3 - <<'PY'
from pathlib import Path
from xml.sax.saxutils import escape
import os

project_id = os.environ["FIREBASE_PROJECT_ID"]
api_key = os.environ["FIREBASE_ANDROID_API_KEY"]
app_id = os.environ["FIREBASE_ANDROID_APP_ID"]
sender_id = os.environ["FIREBASE_MESSAGING_SENDER_ID"]
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="google_app_id" translatable="false">{escape(app_id)}</string>
    <string name="gcm_defaultSenderId" translatable="false">{escape(sender_id)}</string>
    <string name="google_api_key" translatable="false">{escape(api_key)}</string>
    <string name="google_storage_bucket" translatable="false">{escape(project_id)}.appspot.com</string>
    <string name="project_id" translatable="false">{escape(project_id)}</string>
</resources>
"""
Path("android/app/src/main/res/values").mkdir(parents=True, exist_ok=True)
Path("android/app/src/main/res/values/velixeo_firebase.xml").write_text(xml, encoding="utf-8")
PY

echo "Deterministic Android signing, launcher icons, and Firebase resources are ready."
