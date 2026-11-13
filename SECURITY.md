# Security Policy

## Supported versions

The latest `0.x` release receives security fixes. Older builds do not. Once
`1.0` ships, the current major line will be supported.

## Reporting a vulnerability

Reports about a vulnerability in this fork go to moisesaguiarjunior@gmail.com.
That address is the fork maintainer's contact. Include a description and, if
possible, a minimal reproduction. Do not open a public issue for a security
report. GitHub private vulnerability reporting for this fork is unavailable
until the public repository exists.

Reports about a vulnerability in the upstream project go to
simon.auer@marqably.com, or through
[GitHub private vulnerability reporting](https://github.com/SimonErich/fluvie/security/advisories/new)
on SimonErich/fluvie. That address is the upstream contact. It does not replace
the fork contact, and the upstream project has not endorsed this fork.

## Design guarantees you can hold us to

- FFmpeg is always invoked with **argument lists**, never shell strings. No
  user-supplied path or URL is ever concatenated into a command line.
- External inputs (URLs, file paths, downloaded media, HTML/Mermaid sources)
  are validated before use.
- Network fetches and webview/diagram snapshots honor a strict **allowlist**
  and run time-boxed in a sandboxed environment.
- Temp files live in sandboxed, per-render directories.

If you find code that violates one of these, that is a reportable bug even
without a worked exploit.
