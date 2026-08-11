# Security Policy

## Reporting a vulnerability

Please use GitHub's private security advisory feature for vulnerabilities involving credentials, token refresh, local file access, Keychain access, code signing, or update distribution. Do not open a public issue containing secrets or an exploitable proof of concept.

Include the affected macOS and QuotaMonitor versions, a minimal reproduction, and sanitized logs. Remove tokens, account identifiers, usernames, and credential files.

The repository CI runs `script/security_check.sh` to reject common credentials, private keys, personal home paths, and local authentication files before changes are merged. Contributors should run it locally before every push.

## Supported versions

Security fixes are provided for the latest released version. QuotaMonitor depends on local authentication formats and quota endpoints controlled by third parties; compatibility failures are not automatically security vulnerabilities unless they expose or mishandle user data.
