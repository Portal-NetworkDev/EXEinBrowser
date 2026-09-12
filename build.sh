#!/usr/bin/env bash
set -euo pipefail

SOURCE="https://www.boxedwine.org/boxedwine/build/default"
PATCHED="https://raw.githubusercontent.com/andrewnakas/exebrowser/c6049f9684f3c6895c8f31f361a0a29462793f41/public/boxedwine/build/default"
WEB_RELEASE="https://downloads.sourceforge.net/project/boxedwine.mirror/26R1.0/Boxedwine26R1Web.zip"
BASE_FS="https://boxedwine.org/v2/7/TinyCore15WineBase.zip"
OUT="dist"
RUNTIME="$OUT/boxedwine"
WEB_TMP=".boxedwine-web"

rm -rf "$OUT" "$WEB_TMP"
mkdir -p "$RUNTIME" "$WEB_TMP/unpacked" "$WEB_TMP/root"

for file in boxedwine.js boxedwine.wasm boxedwine.css jszip.min.js; do
  curl -fL --retry 3 --retry-delay 1 "$SOURCE/$file" -o "$RUNTIME/$file"
done

curl -fL --retry 3 --retry-delay 1 "$PATCHED/browserfs.boxedwine.js" -o "$RUNTIME/browserfs.boxedwine.js"
curl -fL --retry 3 --retry-delay 1 "$PATCHED/boxedwine-shell.js" -o "$RUNTIME/boxedwine-shell.js"

curl -fL --retry 3 --retry-delay 1 "$BASE_FS" -o "$WEB_TMP/base.zip"
curl -fL --retry 3 --retry-delay 1 "$WEB_RELEASE" -o "$WEB_TMP/Boxedwine26R1Web.zip"

python3 - <<'PY'
from pathlib import Path
import stat
import zipfile


def extract_zip(zip_path, destination):
    destination = Path(destination).resolve()
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            relative = Path(info.filename)
            target = (destination / relative).resolve()
            if target != destination and destination not in target.parents:
                raise RuntimeError(f"Unsafe zip path: {info.filename}")

            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                link_target = Path(archive.read(info).decode())
                source = (target.parent / link_target).resolve()
                if not source.exists():
                    raise RuntimeError(f"Broken symlink in archive: {info.filename} -> {link_target}")
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists() or target.is_symlink():
                    target.unlink()
                target.write_bytes(source.read_bytes())
            elif info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as source, target.open("wb") as destination_file:
                    destination_file.write(source.read())


extract_zip(".boxedwine-web/base.zip", ".boxedwine-web/root")
extract_zip(".boxedwine-web/Boxedwine26R1Web.zip", ".boxedwine-web/unpacked")
PY

WINE_ZIP=$(find "$WEB_TMP/unpacked" -type f -name '*.zip' -print0 | while IFS= read -r -d '' file; do
  if python3 -c 'import sys,zipfile; names=zipfile.ZipFile(sys.argv[1]).namelist(); sys.exit(0 if any(n.rstrip("/") in ("bin/wine", "opt/wine/bin/wine") for n in names) else 1)' "$file"; then
    printf '%s\n' "$file"
    break
  fi
done)

if [ -z "$WINE_ZIP" ]; then
  echo "Boxedwine 26R1 Web archive does not contain a Wine filesystem zip"
  exit 1
fi

python3 - "$WINE_ZIP" <<'PY'
import sys
from pathlib import Path
import stat
import zipfile

zip_path = Path(sys.argv[1])
destination = Path(".boxedwine-web/root").resolve()

with zipfile.ZipFile(zip_path) as archive:
    for info in archive.infolist():
        relative = Path(info.filename)
        target = (destination / relative).resolve()
        if target != destination and destination not in target.parents:
            raise RuntimeError(f"Unsafe zip path: {info.filename}")

        mode = info.external_attr >> 16
        if stat.S_ISLNK(mode):
            link_target = Path(archive.read(info).decode())
            source = (target.parent / link_target).resolve()
            if not source.exists():
                raise RuntimeError(f"Broken symlink in archive: {info.filename} -> {link_target}")
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() or target.is_symlink():
                target.unlink()
            target.write_bytes(source.read_bytes())
        elif info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open("wb") as destination_file:
                destination_file.write(source.read())
PY

if ! test -f "$WEB_TMP/root/bin/wine" && ! test -f "$WEB_TMP/root/opt/wine/bin/wine"; then
  echo "Boxedwine root filesystem is missing Wine"
  exit 1
fi

if ! test -f "$WEB_TMP/root/lib/libpthread.so.0"; then
  echo "Boxedwine root filesystem is missing /lib/libpthread.so.0"
  exit 1
fi

if test -L "$WEB_TMP/root/lib/libpthread.so.0"; then
  echo "Boxedwine root filesystem still has a symlink for /lib/libpthread.so.0"
  exit 1
fi

(cd "$WEB_TMP/root" && zip -qr "../../$OUT/boxedwine.zip" .)

cp index.html style.css app.js runner.html runner.js "$OUT/"
rm -rf "$WEB_TMP"
