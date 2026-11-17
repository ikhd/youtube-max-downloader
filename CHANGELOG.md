# Changes

## Unreleased · macOS v2 review

- Added single-video URL arguments, help and a read-only dependency check. Finder launch and repeated interactive downloads remain available.
- Made height limits strict for separate and combined streams. Added combined-source fallback for audio extraction and explicit failure on missing fragments.
- Verified the final path after post-processing. Repeated selections preserve an existing matching file, including its embedded metadata. Concurrent attempts for the same video are locked.
- Preserved download errors on session exit and handled partial menu input, Ctrl-C and temporary-file cleanup.
- Added bilingual documentation, screenshots from the running CLI, offline regression tests and a live-download verification record.

## Windows trial

- Added a ZIP that runs after extraction without Git. The CMD launcher installs missing Deno, yt-dlp and FFmpeg packages through WinGet and checks for ffprobe.
- Removed Deno’s startup notice about optional aria2c. Turbo works with yt-dlp’s native fragment downloader when aria2c is absent.
