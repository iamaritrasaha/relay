#!/usr/bin/env bash

set -euo pipefail

readonly UUID='relay@foresight.app'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_DIR="$SCRIPT_DIR/$UUID"
readonly DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly DEST_ROOT="$DATA_HOME/gnome-shell/extensions"
readonly DEST_DIR="$DEST_ROOT/$UUID"

if [[ ! -d "$SOURCE_DIR" ]]; then
  printf 'Relay extension source is missing: %s\n' "$SOURCE_DIR" >&2
  exit 1
fi

validate_metadata() {
  python3 - "$1" "$UUID" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
try:
    metadata = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Invalid extension metadata at {path}: {error}")
actual = metadata.get("uuid")
if actual != expected:
    raise SystemExit(f"Extension UUID mismatch: directory is {expected!r}, metadata is {actual!r}")
versions = metadata.get("shell-version")
if not isinstance(versions, list) or not versions:
    raise SystemExit("Extension metadata must declare at least one GNOME Shell version")
PY
}

validate_metadata "$SOURCE_DIR/metadata.json"
mkdir -p -- "$DEST_ROOT"

stage_dir="$(mktemp -d "$DEST_ROOT/.relay-extension.XXXXXX")"
backup_dir=''

cleanup() {
  if [[ -n "$stage_dir" && -e "$stage_dir" ]]; then
    rm -rf -- "$stage_dir"
  fi
  if [[ -n "$backup_dir" && -e "$backup_dir" && ! -e "$DEST_DIR" ]]; then
    mv -- "$backup_dir" "$DEST_DIR"
  fi
}
trap cleanup EXIT

# Dereference any development symlinks while copying. GNOME must receive a
# physical extension under the home filesystem, independent of /media mounts.
cp -aL -- "$SOURCE_DIR/." "$stage_dir/"
validate_metadata "$stage_dir/metadata.json"
if find "$stage_dir" -type l -print -quit | grep -q .; then
  printf 'Refusing to install an extension containing symlinks.\n' >&2
  exit 1
fi

if [[ -e "$DEST_DIR" || -L "$DEST_DIR" ]]; then
  backup_dir="$(mktemp -d "$DEST_ROOT/.relay-extension-old.XXXXXX")"
  rmdir -- "$backup_dir"
  mv -- "$DEST_DIR" "$backup_dir"
fi
mv -- "$stage_dir" "$DEST_DIR"
stage_dir=''
if [[ -n "$backup_dir" ]]; then
  rm -rf -- "$backup_dir"
  backup_dir=''
fi

enabled_value="$(gsettings get org.gnome.shell enabled-extensions)"
updated_value="$(python3 - "$enabled_value" "$UUID" <<'PY'
import ast
import sys

raw = sys.argv[1]
if raw.startswith("@as "):
    raw = raw[4:]
extensions = list(ast.literal_eval(raw))
if sys.argv[2] not in extensions:
    extensions.append(sys.argv[2])
print(repr(extensions))
PY
)"
gsettings set org.gnome.shell enabled-extensions "$updated_value"

shell_knows_extension=false
if gnome-extensions info "$UUID" >/dev/null 2>&1; then
  shell_knows_extension=true
fi

if [[ "$shell_knows_extension" == true ]]; then
  gnome-extensions disable "$UUID" >/dev/null 2>&1 || true
  gdbus call --session \
    --dest org.gnome.Shell.Extensions \
    --object-path /org/gnome/Shell/Extensions \
    --method org.gnome.Shell.Extensions.ReloadExtension \
    "$UUID" >/dev/null 2>&1 || true
  gnome-extensions enable "$UUID"
  printf 'Relay GNOME integration updated and enabled in this session.\n'
else
  # ReloadExtension can rediscover a known local extension on some Shell
  # versions. GNOME 46 Wayland generally cannot discover a first install until
  # a new login session, but trying this harmless method gives the current
  # Shell every supported opportunity before reporting that requirement.
  gdbus call --session \
    --dest org.gnome.Shell.Extensions \
    --object-path /org/gnome/Shell/Extensions \
    --method org.gnome.Shell.Extensions.ReloadExtension \
    "$UUID" >/dev/null 2>&1 || true
  if gnome-extensions info "$UUID" >/dev/null 2>&1; then
    gnome-extensions enable "$UUID"
    printf 'Relay GNOME integration installed and enabled in this session.\n'
  else
    printf 'Relay GNOME integration installed and configured. Log out and log back in once to load it.\n'
  fi
fi

printf 'Installed physical copy: %s\n' "$DEST_DIR"
