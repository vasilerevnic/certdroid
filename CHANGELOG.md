# Changelog

Versions use Semantic Versioning. `module/module.prop` holds the release version and
Magisk's monotonically increasing `versionCode`.

## Unreleased

- Group host scripts under `host/` and Android module scripts under `module/`;
  the installed Magisk layout is unchanged.
- Rename the host removal command to `host/uninstall-via-adb.sh` to distinguish
  it from Magisk's required `uninstall.sh` hook.

## 1.1.2 — 2026-10-01

- Permit a same-pass namespace retry when the previous representative exits
  or changes namespace during a failed attempt.
- Accept `-s`/`--serial` for uninstall and report invalid or duplicate arguments.
- Log boot cancellation to Android logcat without recreating purged state.
- Clarify diagnostic-state retention when removing through the Magisk app.

## 1.1.1 — 2026-10-01

- Wait for slow boot completion without holding the activation lock; cancel
  when disabled/removed and keep immediate installer activation nonblocking.
- Limit namespace failures to one attempt per pass, permitting one retry.
- Rotate activation logs at a 1 MiB threshold and add `--purge-state` to removal,
  with recovery/mount checks and preservation of the lock inode.
- Probe OpenSSL using the actual certificate operation, improve conflicting
  module diagnostics, and document per-app root-hiding/unmount limitations.
- Recognize identical PEM and DER certificates without claiming ownership of
  pre-existing user CAs.
- Search the full user-store collision chain and append without reclaiming
  existing slots, avoiding the install-time check/unlink race. Remove trailing
  tombstones during removal while preserving interior lookup continuity.
- Skip only Java-dependent tests when the JDK is unavailable.
- Report unsupported OpenSSL capabilities before certificate preparation or
  installation, and support both checksum tools when building the verifier.
- Remove unused certificate-map output; retain the public packaging allowlist.
- Add regression coverage and isolated Android 14 BusyBox validation.

## 1.1.0 — 2026-09-30

Initial Git-tracked release of the reviewed and device-tested implementation.
This normalizes the existing v1.1 label to v1.1.0; `versionCode` remains 2.

### Added

- Certificate validation, fingerprint-based deduplication, and subject-hash
  collision handling.
- Explicit ADB device selection and configurable Android user-store installation.
- Exact-CA HTTPS verification, reproducible verification utility build commands,
  and a public archive that excludes local certificates and backups.
- Twenty host regression tests and recorded Android 12, 13, and 14 validation.

### Fixed

- Preserve each system/APEX store's stock roots while reconciling added and
  removed certificates across live mount namespaces.
- Serialize installation, activation, and removal; report failures and restore
  prior store contents when replacement fails.
- Apply certificate-store permissions and SELinux labels; avoid accumulating
  redundant owned overlays and verify namespaces after activation.
- Preserve pre-existing user CAs, track module-owned CAs, and use the correct
  system UID for secondary users.
- Reduce certificate comparison overhead with one native comparison per store.

### Compatibility

- Requires Magisk and its BusyBox. Validated on Android 12/API 31 (emulator,
  Magisk 25.2), Android 13/API 33 (test phone, Magisk 30.7), and Android 14/API 34
  (emulator, Magisk 30.7).
