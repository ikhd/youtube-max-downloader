"""Exercise the real Bash entry point with isolated HOME and mock dependencies."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "YouTube-Max-v2.command"
VIDEO = "https://www.youtube.com/watch?v=DemoVideo01"
MOCK = '''import json, os, pathlib, signal, sys, time
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as out:
    print(json.dumps(args), file=out)
if "-F" in args:
    sys.exit(int(os.environ.get("LIST_CODE", 0)))
if "SLEEP" in os.environ:
    time.sleep(15)
if "FAIL" in os.environ:
    sys.exit(int(os.environ["FAIL"]))
if "EMPTY" in os.environ:
    sys.exit(0)
root = pathlib.Path(args[args.index("-P") + 1])
f = root / "Sample [DemoVideo01] [360p] [Original-MKV].mkv"
if "--simulate" in args:
    print(f.with_suffix(".mp4"))
else:
    f.write_bytes(b"mock media")
    index = args.index("--print-to-file")
    pathlib.Path(args[index + 2]).write_text(str(f) + chr(10))
'''


class Cli(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name).resolve() / "test home"
        self.tools = self.home / "bin"
        self.tools.mkdir(parents=True)
        self.log = self.home / "calls"
        tmpdir = self.home / "temp"
        tmpdir.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(tmpdir),
                        PATH=str(self.tools) + ":/usr/bin:/bin", CALLS=str(self.log))
        self.folder = self.home / "Movies" / "YouTube Downloads"
        for name in ("ffmpeg", "ffprobe", "deno", "aria2c"):
            (self.tools / name).symlink_to("/usr/bin/true")
        fake = self.tools / "yt-dlp"
        fake.write_text("#!" + sys.executable + "\n" + MOCK)
        fake.chmod(0o755)

    def run_cli(self, *args, input="", code=0, isolated=False, **settings):
        argv = [str(SCRIPT), *args]
        if isolated:
            # Remove the real Homebrew search paths only for missing-tool tests.
            argv = ["/bin/bash", "-c", 'source "$1"; shift; PATH="$TEST_PATH"; main "$@"',
                    "test", str(SCRIPT), *args]
        r = subprocess.run(argv, input=input, capture_output=True, text=True, timeout=10,
                           env=dict(self.env, TEST_PATH=self.env["PATH"], **settings))
        self.assertEqual(r.returncode, code, r.stdout + r.stderr)
        return r.stdout + r.stderr

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_help_and_arguments(self):
        self.assertIn("Usage", self.run_cli("--help"))
        self.run_cli("--bad", code=2)
        self.run_cli(VIDEO, VIDEO, code=2)
        self.assertFalse(self.folder.exists())

    def test_exit_and_update(self):
        self.assertIn("Goodbye", self.run_cli())
        self.assertIn("brew upgrade", self.run_cli(input="u\n\n"))
        self.assertFalse(self.calls())

    def test_reject_non_video_and_deceptive_urls(self):
        urls = ["https://youtube.com/playlist?list=PLabc", "https://youtube.com/@someone",
                "http://youtu.be/DemoVideo01", "https://youtube.com.evil.invalid/watch?v=DemoVideo01",
                "https://youtube.com@evil.invalid/watch?v=DemoVideo01", "--exec",
                VIDEO + "\x1b[2J", "https://youtu.be/tooShort"]
        for url in urls:
            with self.subTest(url=url):
                self.run_cli(url, code=2)
        self.assertFalse(self.calls())

    def test_url_forms_and_canonicalization(self):
        urls = ["https://youtu.be/DemoVideo01?t=2", "https://m.youtube.com/shorts/DemoVideo01",
                "https://www.youtube-nocookie.com/embed/DemoVideo01", "https://youtube.com/live/DemoVideo01",
                "https://music.youtube.com/watch?list=PLsample&v=DemoVideo01&t=10",
                VIDEO + "&name=$(touch;demo)"]
        for url in urls:
            with self.subTest(url=url):
                self.run_cli(url, input="n\n\n\n\n")
                self.assertEqual(self.calls()[-1][-2:], ["--", VIDEO])

    def test_default_arguments(self):
        self.run_cli(VIDEO, input="\n\n\n\n")
        args, = self.calls()
        self.assertEqual(args[args.index("-f")+1], "bv+ba/b")
        self.assertEqual(args[args.index("--concurrent-fragments")+1], "8")
        for flag in ("--continue", "--no-overwrites", "--abort-on-unavailable-fragments", "--no-playlist"):
            self.assertIn(flag, args)
        self.assertNotIn("--downloader", args)

    def test_reprompt_and_show_formats(self):
        out = self.run_cli(input="bad\n" + VIDEO + "\ny\nx\n2\nx\n5\nx\n1\n\n", LIST_CODE="1")
        listing, dl = self.calls()
        self.assertIn("-F", listing)
        self.assertIn("Could not list formats", out)
        self.assertIn("Invalid URL", out)
        self.assertEqual(dl[dl.index("--concurrent-fragments")+1], "4")
        rule = dl[dl.index("-f")+1]
        self.assertIn("vcodec^=avc1", rule)
        self.assertIn("acodec^=mp4a", rule)
        self.assertEqual(rule.count("[height<=1080]"), 2)

    def test_quality_caps_and_mp4(self):
        for menu, cap in enumerate((4320, 2160, 1440, 1080, 720, 480, 360), 2):
            self.run_cli(VIDEO, input=f"n\n3\n{menu}\n2\n")
            args = self.calls()[-1]
            self.assertEqual(args[args.index("-f")+1], f"bv[height<={cap}]+ba/b[height<={cap}]")
            self.assertEqual(args[args.index("--remux-video")+1], "mp4")

    def test_audio_skips_quality_and_routes_turbo(self):
        out = self.run_cli(VIDEO, input="n\n4\n3\n")
        args, = self.calls()
        self.assertNotIn("VIDEO QUALITY", out)
        self.assertIn("--extract-audio", args)
        self.assertIn("dash,m3u8:native", args)
        self.assertEqual(args[args.index("--concurrent-fragments")+1], "16")

    def test_optional_aria_absent(self):
        (self.tools/"aria2c").unlink()
        self.assertIn("optional, absent", self.run_cli("--check", isolated=True))
        out = self.run_cli(VIDEO, input="n\n4\n3\n", isolated=True)
        self.assertIn("16 concurrent fragments", out)
        self.assertNotIn("--downloader", self.calls()[-1])

    def test_required_tool_absent(self):
        (self.tools/"ffprobe").unlink()
        self.assertIn("missing", self.run_cli("--check", isolated=True, code=1))
        self.assertIn("brew install ffmpeg", self.run_cli(VIDEO, isolated=True, code=1))
        self.assertFalse(self.calls())

    def test_eof_cancels_each_menu(self):
        for answers in ("", "n\n", "n\n1\n", "n\n1\n1\n"):
            self.run_cli(VIDEO, input=answers, code=130)
        self.assertFalse(self.calls())

    def test_failures_and_cleanup(self):
        self.run_cli(input=VIDEO+"\nn\n\n\n\n\n", FAIL="7", code=7)
        out = self.run_cli(VIDEO, input="n\n\n\n\n", EMPTY="1", code=1)
        self.assertIn("No final media file", out)
        self.assertEqual(list(Path(self.env["TMPDIR"]).iterdir()), [])
        self.assertEqual(list((self.folder/".ytmax-locks").iterdir()), [])

    def test_empty_existing_output_is_preserved_and_reported(self):
        self.folder.mkdir(parents=True)
        empty = self.folder/"Sample [DemoVideo01] [360p] [Original-MKV].mkv"
        empty.touch()
        out = self.run_cli(VIDEO, input="n\n1\n8\n1\n", code=1)
        self.assertIn("output path is occupied", out)
        self.assertEqual(empty.stat().st_size, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn("--simulate", self.calls()[0])

    def test_folder_and_temp_creation_errors(self):
        self.folder.parent.mkdir()
        self.folder.touch()
        self.run_cli(code=1)
        self.folder.unlink()
        self.run_cli(VIDEO, input="n\n\n\n\n", TMPDIR=str(self.home/"missing"), code=1)
        self.assertFalse(self.calls())
        self.assertEqual(list((self.folder/".ytmax-locks").iterdir()), [])

    def test_interrupt_and_same_video_lock(self):
        proc = subprocess.Popen([str(SCRIPT), VIDEO], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, text=True, start_new_session=True,
                                env=dict(self.env, SLEEP="1"))
        try:
            proc.stdin.write("n\n\n\n\n")
            proc.stdin.close()
            for _ in range(100):
                if self.calls():
                    break
                time.sleep(.03)
            self.assertTrue(self.calls())
            self.assertIn("lock this video", self.run_cli(VIDEO, input="n\n\n\n\n", code=1))
            os.killpg(proc.pid, signal.SIGINT)
            self.assertEqual(proc.wait(timeout=5), 130)
            self.assertEqual(list((self.folder/".ytmax-locks").iterdir()), [])
            self.assertEqual(list(Path(self.env["TMPDIR"]).iterdir()), [])
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()


if __name__ == "__main__":
    unittest.main(verbosity=2)
