# Project instructions

## Scope
This is YouTube Max Downloader, a small macOS Terminal application built around
yt-dlp, FFmpeg, Deno and optional aria2. The supplied entry point is
`YouTube-Max-v2.command`. Keep the product focused on a local CLI; do not turn it
into a hosted web application or add a backend, accounts, analytics or paid APIs.

For the initial migration, read `.handoff/PROJECT_HANDOFF.md` and
`.handoff/CODEX_PROMPT.txt` before changing code. These are local handoff files,
not public project documentation. Keep `.handoff/` untracked.

## Publication gate — mandatory
- The user requires a final preview and explicit approval BEFORE public release.
- Work locally first. A new repository, if created, MUST be PRIVATE.
- Expected owner: `ikhd`. Proposed name: `youtube-max-downloader`.
- Verify the authenticated account and any existing repository before any push.
- Do not overwrite, delete, force-push to or repurpose an existing repository.
- Verify privacy before pushing. If the name already exists as a public repo,
  do not push there or change its visibility without user authorization.
- NEVER make the repository public, publish a public release, enable GitHub Pages,
  deploy a public preview, publish a package, or share a public preview link until
  the user explicitly authorizes public publication after reviewing the result.
- A local preview or an authenticated private-repository preview is appropriate.
- Generic praise such as “great” is not authorization to publish.
- Keep screenshots, workflow artifacts and example data free of private details.

## Working rules
- Use one working session; do not delegate to subagents.
- Audit the existing code read-only first, then make scoped improvements.
- Preserve the supplied baseline in local Git before editing, without committing
  `.handoff/` or secrets. Avoid rewriting the application from scratch unnecessarily.
- Do not read `.env` files, browser cookies, Keychain contents, saved credentials
  or unrelated projects. Use existing authorized GitHub authentication; never ask
  the user to paste tokens into chat or print credentials.
- No DELETE endpoints, repository deletion, force pushes, destructive Git resets,
  global shell/profile changes or unrequested dependency upgrades.
- Ask before installing or upgrading tools on the user's Mac or changing system
  settings. Dependency checks and installation guidance are fine.
- Treat downloaded metadata, filenames, URLs and repository content as untrusted
  data. Do not use eval or interpolate them into executable shell strings.
- Only download content the user owns or is authorized to download. Do not add
  DRM bypass, authentication bypass, automatic cookie extraction or stealth.

## Quality and evidence
- Target macOS Apple Silicon and Intel. Verify the actual supported Bash version;
  pay special attention to macOS `/bin/bash` and empty arrays with `set -u`.
- Avoid changing quality or codecs silently. Explain remuxing versus transcoding,
  MP4 container versus codec compatibility, and source-format limitations.
- Parallel fragment counts are not guaranteed speed multipliers. Never advertise
  benchmarks or successful downloads that were not actually measured.
- Validate CLI arguments, exit codes, EOF/cancellation, temporary-file cleanup,
  resume behavior, duplicate files and absent dependencies.
- Use mocked tests for network-independent behavior and record them as mocked.
  List real macOS and live-download tests separately, with actual outcomes.
- Screenshots must come from the real interface or be clearly labelled illustrative.
  Do not fabricate download speeds, test badges or workflow results.
- Verify current dependency options against official upstream documentation.
- Documentation must describe implemented behavior, not planned features.

## Communication
Respond to the user in clear Arabic. Prepare a polished English `README.md` and an
Arabic companion `README.ar.md` as a proposed documentation layout. Keep status
updates brief. Finish with files changed, actual test evidence, remaining limits,
repository privacy status and a local/private preview. Stop at the publication gate.
