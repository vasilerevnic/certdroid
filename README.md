# CertDroid

CertDroid installs a proxy CA (Burp, mitmproxy, or ZAP) into Android's system trust stores through Magisk and reapplies it after reboot.

Use it only on authorized test devices. It does not bypass certificate pinning or an app's custom trust settings.

## Requirements

- Rooted Android device with Magisk and Magisk BusyBox.
- On your computer: Bash, `adb`, `tar`, and OpenSSL with `x509 -ext` support. On macOS, use Homebrew `openssl@3` rather than Apple LibreSSL.
- Tested on Android 12–14 configurations; other versions need device validation.

## Prepare and install

Export your proxy's CA certificate in DER or PEM format, then run from this repository:

```bash
./host/prepare-cert.sh /path/to/proxy-ca.der
./host/install.sh -s DEVICE_SERIAL
```

Use `adb devices` to find the serial. With one connected device, `./host/install.sh` needs no `-s` option. Installation also adds the CA to Android user 0's user store by default; use `--no-user-store`, `--user all`, or `--user ID` if needed.

To replace a CA, remove its old file from `cacerts/`, prepare the new CA, and reinstall. Restart target apps after installation.

## Set the proxy and verify

Configure the proxy in Android's Wi-Fi settings, or set a global proxy:

```bash
adb shell settings put global http_proxy HOST:PORT
```

On an emulator, `10.0.2.2` usually reaches the computer. Then verify the prepared CA:

```bash
./host/trust-test.sh -s DEVICE_SERIAL --ca cacerts/HASH.0 HOST PORT
```

Use the certificate path printed by `prepare-cert.sh`. With one prepared CA and a detectable proxy, `./host/trust-test.sh` needs no arguments. This checks Android's platform trust path; individual apps may behave differently.

If verification fails, inspect the module:

```bash
adb shell 'su -c "sh /data/adb/modules/certdroid/tools/probe.sh"'
adb shell 'su -c "cat /data/adb/certdroid/certdroid.log"'
```

## Remove

```bash
./host/uninstall-via-adb.sh -s DEVICE_SERIAL
adb shell 'settings put global http_proxy :0; settings delete global global_http_proxy_host; settings delete global global_http_proxy_port'
```

To remove diagnostic state too, pass `--purge-state` to the uninstall command. Restart apps or reboot afterward to clear cached trust decisions.
