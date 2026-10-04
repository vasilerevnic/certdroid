# Tools

- `host/trust-test.sh [-s SERIAL] [--ca FILE] [HOST PORT [URL]]`: require default Android
  HTTPS validation and a certificate path to the exact expected CA. If proxy
  detection is ambiguous, pass HOST and PORT explicitly. Multiple prepared CAs
  require `--ca`. All failures exit nonzero.
- `module/probe.sh`: run the installed copy as root to compare actual store contents
  with the recorded desired set across live mount namespaces.
- `module/teardown.sh`: remove only overlays tagged as owned by this module. User CAs
  and boot activation remain; use the host uninstall command to remove managed user trust.
- `host/uninstall-via-adb.sh [SERIAL]`: host entry point for selective module removal.
- `host/build-trust-test.sh`: compile `TrustTest.java` and build `trusttest.dex` plus
  `trusttest.dex.sha256`. Set `D8` if build-tools 37.0.0 is not installed.
- `host/package.sh [OUTPUT.tar.gz]`: public archive with no local CA or backup files.

Device acceptance checks (use a disposable rooted device):

1. Install two different CAs sharing a subject; verify both via their proxies.
2. Remove one local CA, reinstall, and confirm it is no longer trusted while
   the other CA and stock public roots still work.
3. Reinstall unchanged input and inspect mountinfo: no extra owned overlay layers.
4. Check `ls -Zd` and permissions on both store directories and their files,
   then run the trust test from the intended Android user and target app.
5. Exercise a failed mount/label operation and confirm a nonzero result with
   preserved prior trust-store contents.
6. Install for a secondary user, then uninstall; unrelated user certificates
   must remain. Inspect legacy certificates separately when upgrading v1.0.
7. Reboot, restart a zygote on a test image, and rerun activation/probe as needed.

The prebuilt DEX must be rebuilt after editing the Java source.
