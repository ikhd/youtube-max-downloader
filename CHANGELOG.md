# Changes

## Unreleased · macOS v2 review

- Added single-video URL arguments, help and a read-only dependency check. Finder launch and repeated interactive downloads remain available.
- Made height limits strict for separate and combined streams. Added combined-source fallback for audio extraction and explicit failure on missing fragments.
- Verified the final path after post-processing. Repeated selections preserve an existing matching file, including its embedded metadata. Concurrent attempts for the same video are locked.
- Preserved download errors on session exit and handled partial menu input, Ctrl-C and temporary-file cleanup.
- Added bilingual documentation, screenshots from the running CLI, offline regression tests and a live-download verification record.
