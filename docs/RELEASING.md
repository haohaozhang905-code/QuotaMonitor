# Release Guide

QuotaMonitor's public DMG must be signed with a **Developer ID Application** certificate and notarized by Apple. Apple Development, Apple Distribution, and ad-hoc signatures are not substitutes for direct distribution outside the Mac App Store.

## One-time setup

1. Create and install a Developer ID Application certificate for the release team.
2. Create an app-specific password or App Store Connect API key for notarization.
3. Store the credentials in a local keychain profile:

```bash
xcrun notarytool store-credentials QuotaMonitorNotary \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Never commit signing certificates, private keys, passwords, or notarization credentials.

## Build a public release

```bash
export NOTARYTOOL_PROFILE=QuotaMonitorNotary
export QUOTAMONITOR_VERSION=0.1.0
export QUOTAMONITOR_BUILD_NUMBER=1
./script/package_release.sh
```

The script builds a release executable, enables the hardened runtime, adds a secure timestamp, notarizes and staples the app, creates and signs the DMG, notarizes and staples the DMG, then prints its SHA-256 checksum.

Before publishing, install the DMG on a clean standard macOS account and verify launch, official Codex mode, DeepSeek mode, route switching, login-at-startup, and uninstall behavior.

## Local packaging QA

To inspect the DMG layout without release credentials:

```bash
./script/package_release.sh --unsigned
```

This creates a file whose name ends in `UNSIGNED.dmg`. It must never be attached to a public release.
