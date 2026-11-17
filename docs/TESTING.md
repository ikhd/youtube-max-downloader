# Verification record

Local review on **17 November 2026**. Host details came from `sw_vers`, `uname -sm` and each tool’s version command.

| Component | Observed |
| --- | --- |
| Mac | Apple Silicon, Darwin arm64, macOS 27.0 (26A428) |
| System Bash | /bin/bash 3.2.57(1)-release |
| yt-dlp | 2026.10.26 |
| FFmpeg / ffprobe | 9.0.2 / 9.0.2 |
| Deno / aria2c | 2.9.8 / 1.37.0 |
| Test runner | /usr/bin/python3 3.9.6 |

## Reproduce the local checks

Run from the repository root. No dependencies are installed by the test commands.

```sh
/bin/bash -n YouTube-Max-v2.command
./YouTube-Max-v2.command --help
./YouTube-Max-v2.command --check
/usr/bin/python3 tests/test_cli.py
/usr/bin/python3 tests/test_media.py
```

| Check | Observed result |
| --- | --- |
| Syntax and real startup | System Bash accepted the script. Help returned 0. The check found all four required binaries and optional aria2c. The real interactive menus were also exercised in a pseudo-terminal. |
| Mocked CLI regressions | **15 passed.** Isolated test homes and substitute executables. Covers URL and argument validation, playlist rejection, defaults, all caps/profiles, retrying menu input, format-list failure, Turbo fallback, missing tools, unwritable paths, exit status, empty result records and zero-byte outputs, interrupt cleanup and two simultaneous requests for one ID. |
| Local media integration | **5 passed.** FFmpeg generated one-second media. A test-only adapter substituted extractor metadata and real yt-dlp downloaded over loopback. Real FFmpeg merged to all three video profiles, retained H.264/AAC and produced AAC M4A from native AAC and from Opus. ffprobe inspected the output. Turbo completed a direct audio transfer with aria2c available. |
| Partial download | The test server received a byte-range request beginning at **512** when a 512-byte partial MP4 was supplied. The completed file contained H.264 and AAC, and the partial filename disappeared. |
| Duplicate output and unavailable formats | The integration test compared SHA-256 and modification time before and after each repeated video profile. Both stayed identical. Strict caps rejected unknown heights, and the Apple profile rejected a fixture without matching H.264. |

The CLI suite needs Python 3 and macOS system utilities including `shlock`. The integration suite also needs the tools listed above, an FFmpeg build with the test encoders (libx264, AAC and libopus), and local loopback access. A skipped test is reported separately by unittest.

## Live YouTube download

**Big Buck Bunny**, © Blender Foundation. The project licenses its film under CC BY 3.0. This run used the official Blender upload and an isolated test home. The repository does not include the film. [Source and license](https://peach.blender.org/about/) · [Official upload](https://www.youtube.com/watch?v=aqz-KE-bpKQ)

```sh
printf 'n\n1\n8\n1\n' | ./YouTube-Max-v2.command 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'
```

| Setting or observation | Actual result |
| --- | --- |
| Profile / cap / speed | Original-MKV / 360p / Balanced (4 fragments) |
| Exit and output | Exit 0, one verified MKV, 46,073,224 bytes |
| ffprobe | Matroska family, 640 × 360 AV1 video, AAC audio, 634.624 seconds |
| Extractor warning | yt-dlp reported an unrecognized IAMF/Opus codec on an offered format. The selected output contained AAC. |
| Same request repeated after the duplicate fix | Exit 0, existing file reported, SHA-256 and modification time unchanged. |

To inspect a saved file, substitute its actual path.

```sh
ffprobe -v error -show_entries stream=codec_name,width,height:format=format_name,size,duration -of json "FILE.mkv"
```

One earlier repeat exposed yt-dlp rewriting MKV metadata even though the downloader passed `--no-overwrites`. The reviewed script checks for an existing matching final name before invoking post-processing.

## Coverage limits

No native Intel Mac, hosted Actions run, IINA/QuickTime playback session, sustained HLS test, live 4K/8K download or speed comparison was exercised. ShellCheck was unavailable. Only the Original-MKV profile was exercised against live YouTube. Dependency installation and upgrades were not run. The workflow is configured for offline CLI checks on Apple Silicon and Intel macOS runners.

The README images are screenshots of the actual Bash session rendered in xterm.js. The screenshot session stopped in the menus before contacting its example video.

## Windows trial

The owner ran the original launcher on Windows after installing Deno, yt-dlp and FFmpeg, and reached the URL prompt. Deno also printed an information message about the absent optional aria2c executable. The updated launcher checks for it before starting Deno and leaves it out of Deno's subprocess permissions.

On macOS, the updated Windows TypeScript entry point passed Deno check and lint, six CLI tests using substitute executables (including a Turbo download without aria2c), and five local media integration tests using the actual macOS tools. A Windows CI job exercises the CMD launcher with mock installers for first launch, a repeat launch, optional aria2c and failed setup. The local tests did not perform a real WinGet installation.

On 17 November 2026 the project owner also reported that the updated application worked on both a Windows machine and a Mac. The report did not specify a format, OS version or a clean WinGet installation.
