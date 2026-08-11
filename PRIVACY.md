# Privacy

QuotaMonitor is a local macOS utility. It has no QuotaMonitor account system, analytics SDK, advertising, location access, or telemetry service.

## Data accessed on your Mac

- Codex authentication data from the macOS Keychain used by current Codex releases, or `CODEX_HOME/auth.json` / `~/.codex/auth.json` for legacy file-based installations.
- Codex session logs in `~/.codex/sessions` for local token-use aggregation.
- Claude Code transcripts in `~/.claude/projects` (assistant messages only: model, usage counts, timestamp) for local token-use aggregation.
- The cc-switch local database `~/.cc-switch/cc-switch.db` (request log rows for Claude / Claude Desktop: model, token counts, timestamp) when available. This is the only local source of Claude Desktop usage and depends on the cc-switch app running.
- WorkBuddy trace headers in `~/.workbuddy/traces` (the first few kilobytes of each `trace_*.json`, containing only the workflow summary such as total tokens, cached tokens, model names, and timestamps). Full conversation content inside trace files is never read.

No conversation content is read from any of these sources. WorkBuddy trace bodies and Claude transcript message text are intentionally ignored.

## Network requests

- Official Codex quota requests go directly to OpenAI using the current local Codex session.
- DeepSeek balance requests go directly to DeepSeek using the local route configuration.

Credentials are never sent to an intermediary operated by QuotaMonitor. Claude Desktop usage may be missing or stale when cc-switch is not running; QuotaMonitor shows "未采集 / Not captured" instead of estimating. When Claude alone is routed to DeepSeek, QuotaMonitor reads the active provider credential only to call DeepSeek’s official balance endpoint.

## Storage and logging

QuotaMonitor does not store raw authentication tokens in preferences or logs. It stores only the language preference. Operational logs contain refresh status but not credentials.

Security issues involving credentials should be reported privately according to [SECURITY.md](SECURITY.md).
