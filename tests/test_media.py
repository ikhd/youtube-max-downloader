"""Real tools, generated media and synthetic extractor metadata on loopback."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from threading import Thread
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "YouTube-Max-v2.command"
VIDEO = "https://youtu.be/DemoVideo01"
TOOLS = ("yt-dlp", "ffmpeg", "ffprobe", "deno", "shlock")


@unittest.skipUnless(all(shutil.which(p) for p in TOOLS), "requires installed media tools and shlock")
class LocalMedia(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        root = Path(cls.tmp.name)
        cls.sources = {}
        cls.ranges = []

        def generate(name, *args):
            target = root / name
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", *args, str(target)], check=True)
            cls.sources["/" + name] = target.read_bytes()

        video = ["-f", "lavfi", "-i", "testsrc2=s=320x180:r=12:d=1"]
        audio = ["-f", "lavfi", "-i", "sine=frequency=440:duration=1"]
        generate("picture.mp4", *video, "-c:v", "libx264")
        generate("sound.m4a", *audio, "-c:a", "aac")
        generate("sound.opus", *audio, "-c:a", "libopus")
        generate("combined.mp4", *video, *audio, "-c:v", "libx264", "-c:a", "aac")

        class MediaServer(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                data = cls.sources[self.path]
                byte_range = self.headers.get("Range")
                start = 0
                if byte_range:
                    start = int(re.fullmatch(r"bytes=(\d+)-", byte_range).group(1))
                    cls.ranges.append((self.path, start))
                self.send_response(206 if byte_range else 200)
                if byte_range:
                    self.send_header("Content-Range", f"bytes {start}-{len(data)-1}/{len(data)}")
                self.send_header("Content-Length", str(len(data)-start))
                self.end_headers()
                self.wfile.write(data[start:])

        server = ThreadingHTTPServer(("127.0.0.1", 0), MediaServer)
        cls.addClassCleanup(server.server_close)
        Thread(target=server.serve_forever, daemon=True).start()
        cls.addClassCleanup(server.shutdown)
        cls.url = f"http://127.0.0.1:{server.server_port}"

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name).resolve()
        bindir = self.home / "bin"
        bindir.mkdir()
        adapter = bindir / "yt-dlp"
        # Substitute only the extractor. Every downloader and PP option from
        # the application's real command line reaches the installed yt-dlp.
        adapter.write_text("#!" + sys.executable + "\n" +
                           "import os, sys\na = sys.argv[1:]\n" +
                           "assert a[-2:] == ['--', 'https://www.youtube.com/watch?v=DemoVideo01']\n" +
                           "os.execv(os.environ['REAL_YTDLP'], ['yt-dlp', *a[:-2], " +
                           "'--load-info-json', os.environ['INFO']])\n")
        adapter.chmod(0o755)
        self.info = self.home / "source.json"
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(bindir)+":"+os.environ["PATH"],
                        INFO=str(self.info), REAL_YTDLP=shutil.which("yt-dlp"),
                        NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")
        self.folder = self.home / "Movies" / "YouTube Downloads"
        self.folder.mkdir(parents=True)
        self.ranges.clear()

    def source(self, name, vid="none", aud="none", **extra):
        return dict(format_id=name.split(".")[0]+name.split(".")[-1], url=self.url+"/"+name,
                    ext=name.split(".")[-1], vcodec=vid, acodec=aud, **extra)

    def metadata(self, *formats):
        self.info.write_text(json.dumps(dict(id="DemoVideo01", title="Studio sample", extractor="fixture",
                                             extractor_key="Fixture", webpage_url=VIDEO, formats=formats)))

    def download(self, answers, code=0):
        r = subprocess.run([str(SCRIPT), VIDEO], input=answers, env=self.env, text=True,
                           capture_output=True, timeout=40)
        self.assertEqual(r.returncode, code, r.stdout+r.stderr)
        return r.stdout+r.stderr

    def codecs(self, file):
        data = subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(file)])
        return [s["codec_name"] for s in json.loads(data)["streams"]]

    def test_merge_all_video_profiles_and_duplicate(self):
        self.metadata(self.source("picture.mp4", vid="avc1.64000c", height=180, width=320),
                      self.source("sound.m4a", aud="mp4a.40.2"))
        for choice, profile, ext in ((1, "Original-MKV", "mkv"), (2, "Apple-MP4", "mp4"),
                                     (3, "Max-MP4", "mp4")):
            with self.subTest(profile=profile):
                answers = f"n\n{choice}\n8\n1\n"
                self.download(answers)
                final = self.folder/f"Studio sample [DemoVideo01] [180p] [{profile}].{ext}"
                self.assertCountEqual(self.codecs(final), ["h264", "aac"])
                before = (hashlib.sha256(final.read_bytes()).digest(), final.stat().st_mtime_ns)
                self.assertIn("Already downloaded.", self.download(answers))
                self.assertEqual(before, (hashlib.sha256(final.read_bytes()).digest(), final.stat().st_mtime_ns))

    def test_resume_combined_stream(self):
        self.metadata(self.source("combined.mp4", "avc1", "mp4a", height=180, width=320))
        part = self.folder/"Studio sample [DemoVideo01] [180p] [Apple-MP4].mp4.part"
        part.write_bytes(self.sources["/combined.mp4"][:512])
        self.download("n\n2\n8\n1\n")
        self.assertIn(("/combined.mp4", 512), self.ranges)
        self.assertFalse(part.exists())
        self.assertCountEqual(self.codecs(part.with_suffix("")), ["h264", "aac"])

    def test_native_audio_and_opus_conversion(self):
        for name, codec in (("sound.m4a", "mp4a"), ("sound.opus", "opus")):
            self.metadata(self.source(name, aud=codec))
            self.download("n\n4\n1\n")
            final = self.folder/"Studio sample [DemoVideo01] [Audio-M4A].m4a"
            self.assertEqual(self.codecs(final), ["aac"])
            final.unlink()

    @unittest.skipUnless(shutil.which("aria2c"), "requires optional aria2c")
    def test_turbo_direct_audio(self):
        self.metadata(self.source("sound.m4a", aud="mp4a"))
        self.download("n\n4\n3\n")
        final = self.folder/"Studio sample [DemoVideo01] [Audio-M4A].m4a"
        self.assertEqual(self.codecs(final), ["aac"])

    def test_strict_height_and_apple_codec_refusal(self):
        self.metadata(self.source("picture.mp4", vid="avc1"), self.source("sound.m4a", aud="mp4a"))
        self.assertIn("format is not available", self.download("n\n1\n8\n1\n", 1))
        self.metadata(self.source("picture.mp4", vid="av01", height=180), self.source("sound.m4a", aud="mp4a"))
        self.assertIn("format is not available", self.download("n\n2\n1\n1\n", 1))
        self.assertFalse(list(self.folder.glob("*.mp4")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
