#!/usr/bin/env bash
#
# Install the current Relay Linux release build into the user's own prefix so
# GNOME treats it as a real application rather than a binary run out of the
# build tree.
#
# Nothing here needs root: everything lands under $HOME, and the desktop entry
# and icon are published under the application id so the shell can match a
# running Relay window back to its launcher.
#
# Usage:
#   ./linux/install-relay-local.sh            # install the existing release build
#   ./linux/install-relay-local.sh --build    # build the release first, then install
#   ./linux/install-relay-local.sh --uninstall
#
# Safe to re-run: every step replaces what it owns and leaves everything else
# alone.

set -euo pipefail

APP_ID="com.foresight.app.relay"
APP_NAME="Relay"
BINARY_NAME="relay"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_DIR="${APP_DIR}/build/linux/x64/release/bundle"
ASSET_DIR="${APP_DIR}/assets/img"

PREFIX="${HOME}/.local"
INSTALL_DIR="${PREFIX}/opt/${BINARY_NAME}"
BIN_LINK="${PREFIX}/bin/${BINARY_NAME}"
DESKTOP_DIR="${PREFIX}/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_ID}.desktop"
ICON_ROOT="${PREFIX}/share/icons/hicolor"

info() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$1" >&2; }
die() { printf '\033[1;31merror\033[0m %s\n' "$1" >&2; exit 1; }

do_build=0
do_uninstall=0
for arg in "$@"; do
  case "${arg}" in
    --build) do_build=1 ;;
    --uninstall) do_uninstall=1 ;;
    -h|--help) sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: ${arg} (expected --build, --uninstall or no argument)" ;;
  esac
done

# Stops only Relay, and only the copies this script is responsible for: the
# installed bundle and the build tree it was installed from.
stop_relay() {
  local stopped=0 pid exe
  for pid in $(pgrep -x "${BINARY_NAME}" 2>/dev/null || true); do
    exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    case "${exe}" in
      "${INSTALL_DIR}/${BINARY_NAME}"|"${BUNDLE_DIR}/${BINARY_NAME}")
        kill "${pid}" 2>/dev/null || true
        stopped=1
        ;;
    esac
  done
  if [ "${stopped}" -eq 1 ]; then
    info "Stopped the running Relay"
    # Give the window and the tray icon a moment to go away before the files
    # underneath them are replaced.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x "${BINARY_NAME}" >/dev/null 2>&1 || break
      sleep 0.3
    done
  fi
}

refresh_caches() {
  # Both are conveniences. A desktop without them still resolves the entry on
  # its next scan, so neither failing is worth aborting an install over.
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || warn "update-desktop-database reported a problem"
  fi

  # The icon cache is only touched when the user's hicolor tree already carries
  # its own index.theme.
  #
  # This script must never write that file. An index.theme is the authoritative
  # list of directories in a theme, so a generated one silently hides every
  # icon in a size directory it does not happen to name — which is how an
  # earlier version of this installer made unrelated applications lose their
  # icons. Without an index.theme GTK simply scans the tree, which is both
  # correct and what a user-local hicolor directory normally relies on.
  if [ -f "${ICON_ROOT}/index.theme" ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache --force --quiet "${ICON_ROOT}" 2>/dev/null || warn "gtk-update-icon-cache reported a problem"
  fi

  # A cache left behind without its index.theme has the same hiding effect, so
  # point at it rather than deleting a file this script does not own.
  if [ ! -f "${ICON_ROOT}/index.theme" ] && [ -f "${ICON_ROOT}/icon-theme.cache" ]; then
    warn "${ICON_ROOT}/icon-theme.cache exists without an index.theme and can hide icons; remove it with: rm -f '${ICON_ROOT}/icon-theme.cache'"
  fi
}

if [ "${do_uninstall}" -eq 1 ]; then
  stop_relay
  rm -rf "${INSTALL_DIR}"
  rm -f "${BIN_LINK}" "${DESKTOP_FILE}"
  rm -f "${ICON_ROOT}/scalable/apps/${APP_ID}.svg" "${ICON_ROOT}/512x512/apps/${APP_ID}.png"
  refresh_caches
  info "Removed the user-local Relay install"
  exit 0
fi

if [ "${do_build}" -eq 1 ]; then
  info "Building the Linux release"
  # The repo pins its Flutter version through fvm; fall back only if it is absent.
  if command -v fvm >/dev/null 2>&1; then
    (cd "${APP_DIR}" && fvm flutter build linux --release)
  elif command -v flutter >/dev/null 2>&1; then
    warn "fvm not found — building with the system Flutter, which may not match .fvmrc"
    (cd "${APP_DIR}" && flutter build linux --release)
  else
    die "neither fvm nor flutter is on PATH"
  fi
fi

[ -x "${BUNDLE_DIR}/${BINARY_NAME}" ] || die "no release bundle at ${BUNDLE_DIR} — run this script with --build first"
[ -f "${ASSET_DIR}/relay-icon-linux.svg" ] || die "missing ${ASSET_DIR}/relay-icon-linux.svg"
[ -f "${ASSET_DIR}/relay-icon-linux-512.png" ] || die "missing ${ASSET_DIR}/relay-icon-linux-512.png"

stop_relay

# Stage the whole bundle beside the target and swap it in, so an interrupted
# copy never leaves a half-replaced application behind.
info "Installing the bundle into ${INSTALL_DIR}"
mkdir -p "${PREFIX}/opt" "${PREFIX}/bin" "${DESKTOP_DIR}" "${ICON_ROOT}/scalable/apps" "${ICON_ROOT}/512x512/apps"
STAGING_DIR="${INSTALL_DIR}.staging.$$"
rm -rf "${STAGING_DIR}"
cp -a "${BUNDLE_DIR}/." "${STAGING_DIR}/"
rm -rf "${INSTALL_DIR}.previous"
[ -d "${INSTALL_DIR}" ] && mv "${INSTALL_DIR}" "${INSTALL_DIR}.previous"
mv "${STAGING_DIR}" "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}.previous"

info "Linking ${BIN_LINK}"
ln -sfn "${INSTALL_DIR}/${BINARY_NAME}" "${BIN_LINK}"

info "Installing the icon into the user hicolor theme"
install -m 0644 "${ASSET_DIR}/relay-icon-linux.svg" "${ICON_ROOT}/scalable/apps/${APP_ID}.svg"
install -m 0644 "${ASSET_DIR}/relay-icon-linux-512.png" "${ICON_ROOT}/512x512/apps/${APP_ID}.png"

# The desktop entry is named after the GTK application id on purpose. The
# window's Wayland app_id (and its X11 WM_CLASS) is that id, and the shell finds
# a window's launcher by looking for the entry of the same name — without this
# it falls back to showing the raw id and a generic icon.
info "Writing ${DESKTOP_FILE}"
cat > "${DESKTOP_FILE}" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.5
Name=${APP_NAME}
GenericName=Device Continuity
Comment=One desktop for all the devices around you
Exec=${INSTALL_DIR}/${BINARY_NAME}
Icon=${APP_ID}
Terminal=false
Categories=Network;FileTransfer;
Keywords=Relay;Share;Files;Devices;Phone;Clipboard;
StartupNotify=true
StartupWMClass=${APP_ID}
X-GNOME-UsesNotifications=true
DESKTOP
chmod 0644 "${DESKTOP_FILE}"

# An entry left over from an earlier install under the package name would show
# up as a second, iconless "Relay" in the launcher.
STALE_ENTRY="${DESKTOP_DIR}/${BINARY_NAME}.desktop"
if [ -f "${STALE_ENTRY}" ] && grep -q "Name=${APP_NAME}" "${STALE_ENTRY}" 2>/dev/null; then
  rm -f "${STALE_ENTRY}"
  info "Removed the superseded user entry ${STALE_ENTRY}"
fi

refresh_caches

if command -v desktop-file-validate >/dev/null 2>&1; then
  if desktop-file-validate "${DESKTOP_FILE}"; then
    info "Desktop entry validates cleanly"
  else
    warn "desktop-file-validate reported the issues above"
  fi
fi

# A system-wide package would win over this entry, so say so rather than
# touching anything outside $HOME.
if [ -e "/usr/share/applications/${APP_ID}.desktop" ] || [ -e "/usr/share/applications/${BINARY_NAME}.desktop" ]; then
  warn "a system-wide Relay entry exists in /usr/share/applications and may take precedence; remove that package if the launcher shows the wrong Relay"
fi

case ":${PATH}:" in
  *":${PREFIX}/bin:"*) ;;
  *) warn "${PREFIX}/bin is not on PATH, so the 'relay' command will not resolve in a terminal" ;;
esac

info "Relay is installed. Launch it from the GNOME launcher, or with: gtk-launch ${APP_ID}"
