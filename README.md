<p align="center">
  <img src="Sources/QuotaMonitor/Resources/AppIcon.png" width="128" alt="QuotaMonitor icon">
</p>

<h1 align="center">QuotaMonitor</h1>

<p align="center">A native macOS menu-bar dashboard for quota, balance, and local AI token usage.</p>

## What it does

- Shows official Codex session/weekly quota, reset time, and reset credits in the menu bar and main panel.
- Detects Codex and Claude routes independently. When either route uses DeepSeek, it shows the shared DeepSeek balance and estimates its remaining days.
- The main panel is split into two tasks: **Quota monitor** for remaining quota and reset times, and **Token dashboard** for usage by today, the last 7 days, or the last 30 days.
- Token dashboard data can be viewed by platform (Codex, Claude, WorkBuddy, and future sources such as Kimi) or by the actual model name. A Claude request routed through DeepSeek remains Claude in the platform view and DeepSeek in the model/provider view.
- Reads local token usage from Codex, Claude Code, Claude Desktop (through cc-switch), and WorkBuddy; model-level buckets are retained for trend and ranking views.
- Uses the current Codex Keychain credential store when available, while retaining compatibility with legacy `auth.json` installations.
- Has no dashboard server, account system, analytics, or telemetry backend.

## Supported sources

| Source | What QuotaMonitor reads | Notes |
| --- | --- | --- |
| Codex | Official quota endpoint and local session logs | New Codex versions store login credentials in the macOS Keychain; older file-based credentials are still supported. |
| Claude Code | Local project transcripts | Token usage only; Anthropic official quota is not currently available. |
| Claude Desktop | cc-switch request-log database | cc-switch is the available source for this usage. When it is not running, the desktop column is marked as not captured. |
| WorkBuddy | Trace-file summaries | Only the compact trace summary is read, never conversation bodies. |
| DeepSeek | Official balance endpoint | Uses the active Codex or Claude/cc-switch DeepSeek credential and treats the balance as a shared pool. |

## How the numbers are calculated

- **Token total:** input tokens plus output tokens. Cache hits, cache writes, and reasoning tokens remain available as details, rather than being counted again.
- **DeepSeek usage:** requests whose recorded model name contains `deepseek`.
- **Estimated remaining days:** DeepSeek balance divided by the average estimated DeepSeek cost across the latest seven calendar days, capped at 30 days. This is an estimate, because model selection and cache behavior affect actual billing.

## Installation

When a notarized build is published, download `QuotaMonitor-x.y.z.dmg` from [GitHub Releases](https://github.com/MeowkingCP/QuotaDot/releases), drag QuotaMonitor to Applications, then launch it after signing in to Codex. If you use DeepSeek through Claude, keep the active provider configured in Claude or cc-switch so its balance credential can be read locally.

## Privacy

QuotaMonitor reads local authentication credentials and usage records only to fetch quota/balance and calculate local usage. It sends requests directly to OpenAI or DeepSeek. It has no analytics, account system, location access, or telemetry backend. See [PRIVACY.md](PRIVACY.md).

## Local development

Requirements: macOS 14+, Xcode Command Line Tools, and Swift 6. The release build is universal for Apple silicon and Intel Macs.

```bash
swift test
./script/build_and_run.sh --verify
```

To build a local release package, run `./script/package_release.sh --unsigned`. For a public release, use a Developer ID Application certificate and Apple notarization as documented in [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE) © 2026 QuotaMonitor Contributors
