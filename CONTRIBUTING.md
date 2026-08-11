# Contributing to QuotaMonitor

Thanks for helping improve QuotaMonitor.

## Before opening a change

1. Search existing issues and keep each change focused.
2. Never attach `auth.json`, Keychain exports, access tokens, full usernames, or precise location data.
3. For quota parsing changes, include a sanitized fixture or focused unit test.
4. For visual changes, include before/after screenshots with personal information removed.

## Development checks

```bash
./script/security_check.sh
swift test
./script/build_and_run.sh --verify
```

Pull requests should explain the user-visible behavior, the source of truth used for quota data, and how the change was verified. Avoid adding analytics, remote configuration, or a new network service without a separate privacy discussion.

By contributing, you agree that your contribution is licensed under the MIT License.
