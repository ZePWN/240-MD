import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts/install.sh"

MOCK = """#!/bin/bash
set -eu
cmd="${0##*/}"
case "$cmd" in
    uname) echo "${FAKE_ARCH:-aarch64}" ;;
    id)
        case "${1:-}" in
            -un) echo "${FAKE_LOGIN:-alice}" ;;
            -u)
                case "${2:-alice}" in
                    root) echo 0 ;;
                    alice|zepwn) echo 1000 ;;
                    *) exit 1 ;;
                esac ;;
            *) [ "${1:-alice}" = alice ] || [ "${1:-}" = zepwn ] ;;
        esac ;;
    sudo)
        printf '%s\\n' "$*" >> "$FAKE_ROOT/commands"
        case "$1" in
            tee)
                mkdir -p "$FAKE_ROOT$(dirname "$2")"
                cat > "$FAKE_ROOT$2" ;;
            apt-get|udevadm|mkdir|cp|chown|chmod|systemctl) : ;;
            *) echo "Unexpected sudo command: $*" >&2; exit 1 ;;
        esac ;;
    cmake)
        if [ "$1" = "--install" ]; then
            mkdir -p "$DESTDIR/usr/local/bin" "$DESTDIR/usr/local/share/240mp"
            printf '#!/bin/sh\\n' > "$DESTDIR/usr/local/bin/240mp"
            chmod +x "$DESTDIR/usr/local/bin/240mp"
            touch "$DESTDIR/usr/local/share/240mp/Main.qml"
        fi ;;
    curl)
        if [ "$1" = "-fsSL" ] && [ "$2" = "-o" ]; then
            cp "$FAKE_ROOT/assets/${4##*/}" "$3"
        else
            printf '{"tag_name":"v1.2.3"}\\n'
        fi ;;
    systemctl)
        if [ "${1:-}" = show ]; then
            printf '%s\\n' "${FAKE_SERVICE_USER:-}"
        else
            printf '%s\\n' "$*" >> "$FAKE_ROOT/systemctl"
        fi ;;
    *) echo "Unexpected command: $cmd" >&2; exit 1 ;;
esac
"""


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        bindir = self.base / "bin"
        bindir.mkdir()
        mock = bindir / "mock"
        mock.write_text(MOCK)
        mock.chmod(0o755)
        for name in ("uname", "id", "sudo", "cmake", "curl", "systemctl"):
            (bindir / name).symlink_to(mock)
        self.env = os.environ.copy()
        self.env.update(
            PATH=f"{bindir}:/usr/bin:/bin",
            FAKE_ROOT=str(self.base),
            SUDO_USER="alice",
        )
        self.env.pop("FAKE_ARCH", None)

    def run_installer(self, *args, installer=INSTALLER, **env):
        return subprocess.run(
            ["bash", str(installer), *map(str, args)],
            env={**self.env, **env},
            text=True,
            capture_output=True,
        )

    def make_release(self, valid=True):
        assets = self.base / "assets"
        assets.mkdir()
        app = self.base / "payload/usr/local/bin/240mp"
        app.parent.mkdir(parents=True)
        app.write_text("#!/bin/sh\n")
        app.chmod(0o755)
        qml = self.base / "payload/usr/local/share/240mp/Main.qml"
        qml.parent.mkdir(parents=True)
        qml.touch()
        filename = "240-MP-v1.2.3-linux-arm64.tar.gz"
        archive = assets / filename
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(self.base / "payload/usr", arcname="usr")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest() if valid else "0" * 64
        (assets / "SHA256SUMS").write_text(f"{digest}  {filename}\n")

    def test_source_install_enables_kiosk_without_prompts(self):
        result = self.run_installer("--source", ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        unit = (self.base / "etc/systemd/system/240mp.service").read_text()
        self.assertIn("User=alice", unit)
        self.assertIn("Environment=QT_QPA_PLATFORM=eglfs", unit)
        commands = (self.base / "commands").read_text()
        self.assertIn("systemctl enable 240mp.service", commands)
        self.assertIn("--no-install-recommends", commands)
        self.assertNotIn("qt6-wayland", commands)

    def test_no_autostart_does_not_create_service(self):
        result = self.run_installer("--source", ROOT, "--no-autostart")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.base / "etc/systemd/system/240mp.service").exists())

    def test_source_directory_can_follow_user_option(self):
        result = self.run_installer("--source", "--user", "zepwn", ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        unit = (self.base / "etc/systemd/system/240mp.service").read_text()
        self.assertIn("User=zepwn", unit)

    def test_missing_source_directory_and_user_are_reported(self):
        result = self.run_installer("--source", "--user", "zepwn")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--source requires a 240-MP checkout", result.stderr)
        result = self.run_installer("--user", "--source", ROOT)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--user requires", result.stderr)
        self.assertFalse((self.base / "commands").exists())

    def test_stale_service_owner_reports_the_selected_account(self):
        unit_path = self.base / "existing.service"
        unit_path.touch()
        installer = self.base / "install.sh"
        installer.write_text(INSTALLER.read_text().replace(
            'SYSTEMD_SERVICE="/etc/systemd/system/240mp.service"',
            f'SYSTEMD_SERVICE="{unit_path}"',
        ))
        result = self.run_installer("--source", ROOT, installer=installer, FAKE_SERVICE_USER="pi")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selected account 'pi' does not exist", result.stderr)
        self.assertFalse((self.base / "commands").exists())
        result = self.run_installer("--source", "--user", "zepwn", ROOT,
                                    installer=installer, FAKE_SERVICE_USER="pi")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_release_checksum_is_required(self):
        self.make_release(valid=False)
        result = self.run_installer("v1.2.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum verification failed", result.stderr)
        self.assertFalse((self.base / "etc/systemd/system/240mp.service").exists())

    def test_valid_release_is_installed(self):
        self.make_release()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.base / "etc/systemd/system/240mp.service").exists())

    def test_rejects_bad_user_and_arch_before_changes(self):
        for args, env in [(("--user", "root"), {}), ((), {"FAKE_ARCH": "x86_64"})]:
            result = self.run_installer(*args, **env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.base / "commands").exists())

    def test_rejects_source_with_release_and_invalid_parallelism(self):
        result = self.run_installer("v1.2.3", "--source", ROOT)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / "commands").exists())
        result = self.run_installer("--source", ROOT, CMAKE_BUILD_PARALLEL_LEVEL="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be a positive integer", result.stderr)
        self.assertFalse((self.base / "etc/systemd/system/240mp.service").exists())

    def test_stop_helper_only_powers_off_for_clean_app_exit(self):
        result = self.run_installer("--source", ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        helper = self.base / "usr/local/bin/240mp-stop"
        for code, status, service_result, expected in (
            ("exited", "0", "success", "poweroff"),
            ("exited", "10", "exit-code", "start 240mp-terminal.service"),
            ("exited", "11", "exit-code", ""),
            ("exited", "12", "exit-code", "reboot"),
            ("exited", "1", "exit-code", ""),
            ("killed", "15", "success", ""),
        ):
            log = self.base / "systemctl"
            log.unlink(missing_ok=True)
            subprocess.run(
                ["bash", str(helper)],
                env={**self.env, "EXIT_CODE": code, "EXIT_STATUS": status, "SERVICE_RESULT": service_result},
                check=True,
            )
            self.assertEqual(log.read_text().strip() if log.exists() else "", expected)


if __name__ == "__main__":
    unittest.main()
