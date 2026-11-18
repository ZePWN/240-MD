#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 240-MP installer for Raspberry Pi OS Trixie (arm64)
#
# Usage:
#   bash install.sh [version | --source DIR] [--user USER] [--no-autostart]
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="ZePWN/240-MD"
INSTALL_DIR="/opt/240mp"
LAUNCHER="/usr/local/bin/240mp"
SYSTEMD_SERVICE="/etc/systemd/system/240mp.service"

VERSION="latest"
VERSION_SET=0
AUTOSTART=1
OWNER_USER=""
SOURCE_DIR=""
SOURCE_REQUESTED=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: --user requires an existing non-root username." >&2
                exit 1
            fi
            OWNER_USER="$2"
            shift 2
            ;;
        --no-autostart) AUTOSTART=0; shift ;;
        --source)
            if [ "$SOURCE_REQUESTED" -eq 1 ]; then
                echo "Error: specify --source only once." >&2
                exit 1
            fi
            SOURCE_REQUESTED=1
            shift
            if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
                SOURCE_DIR="$1"
                shift
            fi
            ;;
        -h|--help)
            echo "Usage: bash install.sh [version | --source DIR] [--user USER] [--no-autostart]"
            exit 0
            ;;
        -*)
            echo "Error: unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ "$SOURCE_REQUESTED" -eq 1 ] && [ -z "$SOURCE_DIR" ]; then
                SOURCE_DIR="$1"
                shift
                continue
            fi
            if [ "$VERSION_SET" -eq 1 ]; then
                echo "Error: specify at most one release version." >&2
                exit 1
            fi
            VERSION="$1"
            VERSION_SET=1
            shift
            ;;
    esac
done

if [ "$SOURCE_REQUESTED" -eq 1 ]; then
    if [ "$VERSION_SET" -eq 1 ] || [ ! -f "$SOURCE_DIR/CMakeLists.txt" ] || [ ! -f "$SOURCE_DIR/Main.qml" ]; then
        echo "Error: --source requires a 240-MP checkout and cannot be combined with a release version." >&2
        exit 1
    fi
    SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
fi

# ── Verify architecture ────────────────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "Error: this installer is for arm64 (aarch64). Detected: $ARCH" >&2
    exit 1
fi

# Preserve an existing non-root service owner when updating over SSH.
EXISTING_USER=""
if [ -f "$SYSTEMD_SERVICE" ]; then
    EXISTING_USER=$(systemctl show 240mp.service --property=User --value)
fi
if [ -z "$OWNER_USER" ] && [ -n "$EXISTING_USER" ]; then
    if [[ "$EXISTING_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
        && EXISTING_UID=$(id -u "$EXISTING_USER" 2>/dev/null) \
        && [ "$EXISTING_UID" -ne 0 ]; then
        OWNER_USER="$EXISTING_USER"
    else
        echo "Warning: existing service account '${EXISTING_USER}' is invalid or root; using the invoking user instead." >&2
    fi
fi
if [ -z "$OWNER_USER" ]; then
    OWNER_USER="$(id -un)"
    if [ "$OWNER_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
        OWNER_USER="$SUDO_USER"
    fi
fi
if [[ ! "$OWNER_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "Error: selected account '${OWNER_USER}' has an unsupported username; use --user USER." >&2
    exit 1
fi
if ! OWNER_UID=$(id -u "$OWNER_USER" 2>/dev/null); then
    echo "Error: selected account '${OWNER_USER}' does not exist; use --user USER." >&2
    exit 1
fi
if [ "$OWNER_UID" -eq 0 ]; then
    echo "Error: selected account '${OWNER_USER}' is root; run as your normal user or use --user USER." >&2
    exit 1
fi
if [ "$AUTOSTART" -eq 0 ] && [ -n "$EXISTING_USER" ] && [ "$OWNER_USER" != "$EXISTING_USER" ]; then
    echo "Error: --no-autostart cannot change the existing service owner (${EXISTING_USER})." >&2
    exit 1
fi
echo "Installing for user ${OWNER_USER}."

# ── Install runtime dependencies ──────────────────────────────────────────────
echo "Installing runtime dependencies..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    ca-certificates curl python3 \
    dbus polkitd \
    libqt6quick6 \
    libqt6qml6 \
    libqt6opengl6 \
    libqt6network6 \
    libqt6svg6 \
    qt6-svg-plugins \
    qml6-module-qtqml \
    qml6-module-qtqml-workerscript \
    qml6-module-qtquick \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-window \
    qml6-module-qtquick-effects \
    libsdl2-2.0-0 \
    libpcsclite1 \
    udisks2 \
    mpv

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
STAGE_DIR="${TMP_DIR}/stage"
if [ -n "$SOURCE_DIR" ]; then
    BUILD_JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
    if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: CMAKE_BUILD_PARALLEL_LEVEL must be a positive integer." >&2
        exit 1
    fi
    echo "Installing build dependencies..."
    sudo apt-get install -y --no-install-recommends \
        build-essential cmake pkg-config \
        qt6-base-dev qt6-declarative-dev qt6-svg-dev \
        libdrm-dev libssl-dev libsdl2-dev libpcsclite-dev
    echo "Building from ${SOURCE_DIR} (this can take a while)..."
    cmake -S "$SOURCE_DIR" -B "${TMP_DIR}/build" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
    cmake --build "${TMP_DIR}/build" --parallel "$BUILD_JOBS"
    DESTDIR="$STAGE_DIR" cmake --install "${TMP_DIR}/build"
    VERSION="source build"
else
    if [ "$VERSION" = "latest" ]; then
        echo "Fetching latest release tag..."
        if ! VERSION=$(curl -fsSL \
            "https://api.github.com/repos/${REPO}/releases/latest" \
            | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])"); then
            echo "Error: could not resolve the latest release. If none is published, use --source DIR." >&2
            exit 1
        fi
    fi
    if [[ ! "$VERSION" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        echo "Error: invalid release version: ${VERSION}" >&2
        exit 1
    fi
    TARBALL="240-MP-${VERSION}-linux-arm64.tar.gz"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"
    echo "Downloading and verifying ${TARBALL}..."
    curl -fsSL -o "${TMP_DIR}/${TARBALL}" "${DOWNLOAD_URL}"
    curl -fsSL -o "${TMP_DIR}/SHA256SUMS" \
        "https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
    if ! (cd "$TMP_DIR" &&
        awk -v file="$TARBALL" '$2 == file && NF == 2 { print; count++ } END { if (count != 1) exit 1 }' SHA256SUMS > checksum &&
        sha256sum --check --strict checksum); then
        echo "Error: release checksum verification failed for ${TARBALL}." >&2
        exit 1
    fi
    mkdir -p "$STAGE_DIR"
    tar -xzf "${TMP_DIR}/${TARBALL}" -C "$STAGE_DIR"
fi
if [ ! -x "${STAGE_DIR}/usr/local/bin/240mp" ] || [ ! -f "${STAGE_DIR}/usr/local/share/240mp/Main.qml" ]; then
    echo "Error: the build or release is missing the application or its resources." >&2
    exit 1
fi

# ── udev rule: allow tty group to open /dev/tty0 for VT switching ─────────────
echo 'KERNEL=="tty0", GROUP="tty", MODE="0620"' \
    | sudo tee /etc/udev/rules.d/99-240mp-tty.rules > /dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger /dev/tty0

# Expose kernel HDMI-CEC adapters to the headless app service.
echo 'KERNEL=="cec[0-9]*", GROUP="video", MODE="0660"' \
    | sudo tee /etc/udev/rules.d/99-240mp-cec.rules > /dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=cec

# Allow this app user to mount non-system filesystems through UDisks2
# without an interactive desktop Polkit session. System-device mounts still use
# UDisks2's separate, administrator-only action.
POLKIT_RULE="/etc/polkit-1/rules.d/60-240mp-usb-mount.rules"
sudo tee "${POLKIT_RULE}" > /dev/null <<POLKIT_RULE_CONTENT
polkit.addRule(function(action, subject) {
    if (subject.user == "${OWNER_USER}" &&
        (action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat")) {
        return polkit.Result.YES;
    }
});
POLKIT_RULE_CONTENT

# ── Extract to install directory ───────────────────────────────────────────────
# Both installation sources are staged with the usr/local prefix.
echo "Installing to ${INSTALL_DIR}..."
sudo mkdir -p "${INSTALL_DIR}"
sudo cp -a "${STAGE_DIR}/usr/local/." "${INSTALL_DIR}/"

# Owned by the running user so the launcher can swap in staged in-app updates.
sudo chown -R "${OWNER_USER}:" "${INSTALL_DIR}"

# ── Create launcher ────────────────────────────────────────────────────────────
echo "Creating launcher at ${LAUNCHER}..."
sudo tee "${LAUNCHER}" > /dev/null << 'LAUNCHER_SCRIPT'
#!/usr/bin/env bash
# 240-MP launcher — applies staged in-app updates, then auto-detects the
# display platform and execs the binary.
INSTALL_DIR="/opt/240mp"

# Tells the app this launcher knows how to apply staged updates; the in-app
# updater refuses to stage anything without it (older installs must re-run
# this installer once to pick up the launcher/240mp-stop contract).
export MP240_LAUNCHER_API=1

# ── Apply a staged in-app update ───────────────────────────────────────────────
# The app downloads the release tarball to DATA_ROOT/updates and writes
# staged.sha256 ("<sha256>  <tarball>", coreutils format). Applied here, before
# exec, so it works identically for manual runs, desktop sessions, and the
# autostart service (which relaunches through this script on exit code 11 —
# see 240mp-stop). Mirror any DATA_ROOT override into the app's environment
# (e.g. the systemd unit) or this block won't find the staging directory.
UPDATES_DIR="${DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/240-MP}/updates"

# Crash recovery: a previous apply died between the child renames below.
if [ ! -x "$INSTALL_DIR/bin/240mp" ] && [ -x "$INSTALL_DIR/.new/bin/240mp" ]; then
    for d in "$INSTALL_DIR"/.new/*; do mv -f "$d" "$INSTALL_DIR/"; done
    rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
fi

if [ -f "$UPDATES_DIR/staged.sha256" ] && [ -w "$INSTALL_DIR" ]; then
    if ( cd "$UPDATES_DIR" && sha256sum -c --status staged.sha256 ); then
        STAGED_TARBALL=$(awk '{print $2}' "$UPDATES_DIR/staged.sha256")
        rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
        mkdir -p "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
        # Extract fully, then swap top-level dirs (bin, share) via rename —
        # shrinks the power-loss window from the whole extraction to two mv's,
        # and drops files that no longer exist in the new release.
        if tar -xzf "$UPDATES_DIR/$STAGED_TARBALL" --strip-components=3 -C "$INSTALL_DIR/.new" \
           && [ -x "$INSTALL_DIR/.new/bin/240mp" ]; then
            for d in "$INSTALL_DIR"/.new/*; do
                name=$(basename "$d")
                [ -e "$INSTALL_DIR/$name" ] && mv "$INSTALL_DIR/$name" "$INSTALL_DIR/.old/$name"
                mv "$d" "$INSTALL_DIR/$name"
            done
            rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
            rm -f "$UPDATES_DIR/$STAGED_TARBALL" "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.json"
        else
            # Bad extract: keep the old tree; .failed stops a retry every boot.
            rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
            mv -f "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.sha256.failed" 2>/dev/null
        fi
    else
        # Corrupt/partial stage — discard; the app re-offers the update.
        rm -f "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.json"
    fi
fi

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
elif [ -n "${DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
else
    # No display server — use EGLFS for headless/kiosk mode (RPi Lite)
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
    export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
    export QT_QPA_EGLFS_KMS_ATOMIC=1

    # Point Qt EGLFS at the DRM card that has a real display pipeline. Render-
    # only nodes (v3d) have no connector dirs under /sys/class/drm and make Qt
    # fail with "drmModeGetResources failed (Operation not supported)". On
    # Pi3B+/Pi4 the display card happens to be card0 (auto-pick works), but on
    # Pi5 the v3d render node often enumerates first, so we must select the
    # right card explicitly. Prefer a connected connector; fall back to the
    # first card that has any connector at all.
    KMS_CARD=""
    for s in /sys/class/drm/card*-*/status; do
        [ -e "$s" ] || continue
        if [ "$(cat "$s")" = "connected" ]; then
            n=$(basename "$(dirname "$s")"); KMS_CARD="${n%%-*}"; break
        fi
    done
    if [ -z "$KMS_CARD" ]; then
        for d in /sys/class/drm/card*-*; do
            [ -e "$d" ] || continue
            n=$(basename "$d"); KMS_CARD="${n%%-*}"; break
        done
    fi
    if [ -n "$KMS_CARD" ] && [ -e "/dev/dri/$KMS_CARD" ]; then
        KMS_CONF="${XDG_RUNTIME_DIR:-/tmp}/240mp-kms.json"
        printf '{ "device": "/dev/dri/%s" }\n' "$KMS_CARD" > "$KMS_CONF"
        export QT_QPA_EGLFS_KMS_CONFIG="$KMS_CONF"
    fi
fi

export QT_QPA_PLATFORM
export QML2_IMPORT_PATH="/usr/lib/aarch64-linux-gnu/qt6/qml"

exec "${INSTALL_DIR}/bin/240mp" "$@"
LAUNCHER_SCRIPT

sudo chmod +x "${LAUNCHER}"

# ── Optional: systemd autostart ───────────────────────────────────────────────
if [ "$AUTOSTART" -eq 1 ]; then
    sudo tee "${SYSTEMD_SERVICE}" > /dev/null << UNIT
[Unit]
Description=240-MP Media Player
After=multi-user.target sound.target

[Service]
Type=simple
User=${OWNER_USER}
SupplementaryGroups=tty video input audio
AmbientCapabilities=CAP_SYS_TTY_CONFIG
Environment=QT_QPA_PLATFORM=eglfs
Environment=QT_QPA_EGLFS_ALWAYS_SET_MODE=1
Environment=QT_QPA_EGLFS_KMS_ATOMIC=1
Environment=QML2_IMPORT_PATH=/usr/lib/aarch64-linux-gnu/qt6/qml
Environment=MP240_AUTOSTART=1
ExecStartPre=+-/usr/bin/systemctl stop 240mp-terminal.service
ExecStart=${LAUNCHER}
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=10 12 13
ExecStopPost=+/usr/local/bin/240mp-stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

    # ExecStopPost helper: explicit power off (exit 13) powers the Pi off; exit 10 means
    # the user chose "Exit to Terminal", so instead spawn a
    # login shell on tty1 (see views/Settings.qml). RestartPreventExitStatus=10 12 13
    # keeps Restart=on-failure from relaunching the app over that shell.
    # Exit 12 is "Reboot" from the Quit dialog: reboot instead of powering off
    # (also listed in RestartPreventExitStatus so the app isn't relaunched mid-reboot).
    # Exit 11 is "Apply & Restart" from the in-app updater (views/Update.qml):
    # do nothing here — it's a failure status, so Restart=on-failure relaunches
    # through the launcher, which applies the staged update before exec.
    sudo tee /usr/local/bin/240mp-stop > /dev/null << 'STOP_HELPER'
#!/usr/bin/env bash
# Called by 240mp.service ExecStopPost. systemd sets $EXIT_STATUS to the app's exit code.
if [ "${EXIT_CODE:-}" = "exited" ] && [ "${EXIT_STATUS:-}" = "13" ]; then
    systemctl poweroff
elif [ "${EXIT_CODE:-}" = "exited" ] && [ "${EXIT_STATUS:-}" = "10" ]; then
    systemctl start 240mp-terminal.service
elif [ "${EXIT_CODE:-}" = "exited" ] && [ "${EXIT_STATUS:-}" = "12" ]; then
    systemctl reboot
fi
STOP_HELPER
    sudo chmod +x /usr/local/bin/240mp-stop

    # On-demand login shell for "Exit to Terminal". Not enabled (no boot race with
    # 240mp.service); getty@tty1 stays masked. Started only by 240mp-stop, and
    # stopped again by 240mp.service's ExecStartPre when the app comes back.
    sudo tee /etc/systemd/system/240mp-terminal.service > /dev/null << 'TERMINAL_UNIT'
[Unit]
Description=240-MP exit-to-terminal login shell

[Service]
Type=idle
ExecStart=-/sbin/agetty --noclear tty1 linux
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
KillMode=process
Restart=no
TERMINAL_UNIT

    sudo systemctl mask getty@tty1.service autovt@.service
    sudo systemctl daemon-reload
    sudo systemctl enable 240mp.service
    echo "Service installed and enabled."
    echo "Reboot to start 240-MP on the local display: sudo reboot"
elif [ -f "$SYSTEMD_SERVICE" ]; then
    echo "Existing autostart service was left unchanged."
fi

echo ""
echo "240-MP ${VERSION} installed successfully."
echo "Logs: sudo journalctl -u 240mp -b"
