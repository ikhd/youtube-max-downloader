# Working on the downloader

Keep the macOS entry point runnable with the system `/bin/bash` 3.2. Use quoted argument arrays at process boundaries. Exercise changed behavior through the actual entry point, and update both README files when a menu or output changes.

```sh
/bin/bash -n YouTube-Max-v2.command
python3 tests/test_cli.py
python3 tests/test_media.py
```

The first suite uses mock tools. The second uses installed media tools and a loopback server serving generated fixtures. It skips when a prerequisite is missing. A live YouTube test requires material you own or have permission to download. Record the selected profile, observed result and platform. [Verification record](docs/TESTING.md)

For a bug report, include the macOS, Bash and yt-dlp versions, menu choices and the shortest relevant error. Replace personal paths, private URLs and titles with neutral examples. For a security issue, contact the maintainer privately before sharing reproduction details. Keep credentials, browser data, downloaded media and local review files out of patches.
