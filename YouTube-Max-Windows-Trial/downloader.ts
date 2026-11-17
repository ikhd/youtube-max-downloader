// Windows trial. Deno is both the local CLI runtime and yt-dlp's JS runtime.
import { basename, dirname, extname, join } from "node:path";
import { createInterface } from "node:readline";
import { stdin, stdout } from "node:process";

const profiles = ["Original-MKV", "Apple-MP4", "Max-MP4", "Audio-M4A"];
const caps = [0, 4320, 2160, 1440, 1080, 720, 480, 360];
const common = [
  "--ignore-config",
  "--encoding",
  "utf-8",
  "--no-playlist",
  "--remote-components",
  "ejs:npm",
];

export function videoId(raw: string): string | undefined {
  // deno-lint-ignore no-control-regex -- reject terminal control characters in pasted input
  if (!raw.startsWith("https://") || /[\s\\\x00-\x1f\x7f]/u.test(raw)) return;
  const match =
    /^https:\/\/(youtu\.be|(?:(?:www|m|music)\.)?youtube\.com|(?:www\.)?youtube-nocookie\.com)\/([^?#]*)(?:\?([^#]*))?(?:#.*)?$/
      .exec(raw);
  if (!match) return;
  const [, host, path, query] = match;
  let id: string | undefined;
  if (host === "youtu.be") id = path.replace(/\/$/, "");
  else if (/^watch\/?$/.test(path)) {
    id = new URLSearchParams(query).get("v") ?? undefined;
  } else id = /^(?:shorts|live|embed|v)\/([\w-]+)\/?$/.exec(path)?.[1];
  return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? id : undefined;
}

export function settings(
  profile: number,
  cap: number,
  speed: number,
  aria: boolean,
) {
  const name = profiles[profile];
  const audio = profile === 3;
  const ext = ["mkv", "mp4", "mp4", "m4a"][profile];
  const h = cap ? `[height<=${cap}]` : "";
  let rule = `bv${h}+ba/b${h}`;
  if (profile === 1) {
    rule =
      `bv[vcodec^=avc1]${h}+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1][acodec^=mp4a]${h}`;
  }
  if (audio) rule = "ba[ext=m4a]/ba/b";
  const template = `%(title).120B [%(id)s]${
    audio ? "" : " [%(height)sp]"
  } [${name}].%(ext)s`;
  const args = [
    ...common,
    "--windows-filenames",
    "--no-overwrites",
    "--continue",
    "--retries",
    "10",
    "--fragment-retries",
    "10",
    "--extractor-retries",
    "3",
    "--abort-on-unavailable-fragments",
    "--concurrent-fragments",
    String([4, 8, 16][speed]),
    "--no-simulate",
    "--progress",
    "--newline",
    "--progress-delta",
    "1",
    "--embed-metadata",
    "--no-embed-info-json",
    "-f",
    rule,
    "-o",
    template,
  ];
  args.push(
    ...(audio
      ? ["--extract-audio", "--audio-format", "m4a"]
      : ["--merge-output-format", ext, "--remux-video", ext]),
  );
  if (speed === 2 && aria) {
    args.push(
      "--downloader",
      "aria2c",
      "--downloader",
      "dash,m3u8:native",
      "--downloader-args",
      "aria2c:-x 8 -s 8 -k 1M --max-tries=5 --retry-wait=2",
    );
  }
  return { name, ext, args };
}

async function installed(program: string, version: string) {
  try {
    return (await new Deno.Command(program, {
      args: [version],
      stdin: "null",
      stdout: "null",
      stderr: "null",
    }).output()).success;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function yt(args: string[], capture = false) {
  return await new Deno.Command("yt-dlp.exe", {
    args,
    stdin: "null",
    stdout: capture ? "piped" : "inherit",
    stderr: "inherit",
  }).output();
}

function isMedia(path: string, folder: string): boolean {
  if (dirname(path) !== folder) return false;
  try {
    const info = Deno.lstatSync(path);
    return info.isFile && info.size > 0;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function download(
  folder: string,
  id: string,
  config: ReturnType<typeof settings>,
) {
  const state = join(folder, ".ytmax-state");
  Deno.mkdirSync(state, { recursive: true });
  const lock = Deno.openSync(join(state, id + ".lock"), {
    create: true,
    write: true,
    read: true,
  });
  const record = join(state, id + ".path");
  try {
    if (!lock.tryLockSync(true)) {
      console.error("This video is already in use.");
      return 1;
    }
    const url = "https://www.youtube.com/watch?v=" + id;
    const args = [...config.args, "-P", folder];
    for (const file of Deno.readDirSync(folder)) {
      if (
        !file.name.includes(` [${id}] `) ||
        !file.name.endsWith(`[${config.name}].${config.ext}`)
      ) continue;
      const probe = await yt([
        ...args,
        "--simulate",
        "--quiet",
        "--no-progress",
        "--print",
        "filename",
        "--",
        url,
      ], true);
      if (!probe.success) return probe.code;
      const raw = new TextDecoder().decode(probe.stdout).replace(
        /[\r\n]+$/,
        "",
      );
      const path = join(
        dirname(raw),
        basename(raw, extname(raw)) + "." + config.ext,
      );
      if (isMedia(path, folder)) {
        console.log("Already downloaded.\n" + path);
        return 0;
      }
      if (dirname(path) !== folder) {
        throw new Error("Unexpected output directory.");
      }
      try {
        Deno.lstatSync(path);
        throw new Error("The output path is occupied.");
      } catch (e) {
        if (!(e instanceof Deno.errors.NotFound)) throw e;
      }
      break;
    }
    Deno.writeTextFileSync(record, "");
    try {
      const r = await yt([
        ...args,
        "--print-to-file",
        "after_move:%(filepath)s",
        record,
        "--",
        url,
      ]);
      if (!r.success) {
        console.error(`Download failed (code ${r.code}).`);
        return r.code;
      }
      const path = Deno.readTextFileSync(record).replace(/[\r\n]+$/, "");
      if (!isMedia(path, folder)) {
        throw new Error("Could not verify the final media file.");
      }
      console.log("File ready.\n" + path);
      return 0;
    } finally {
      Deno.removeSync(record);
    }
  } finally {
    lock.close();
  }
}

async function main() {
  if (Deno.args.length) {
    console.error("Launch without arguments, then paste a video link.");
    return 2;
  }
  const home = Deno.env.get("USERPROFILE");
  if (!home) throw new Error("USERPROFILE is missing.");
  const folder = join(home, "Videos", "YouTube Downloads");
  console.log("YouTube Max Downloader  |  Windows trial\nSave to: " + folder);
  for (
    const [program, version] of [["yt-dlp.exe", "--version"], [
      "ffmpeg.exe",
      "-version",
    ], ["ffprobe.exe", "-version"]]
  ) {
    if (!await installed(program, version)) {
      throw new Error(
        program + " is missing or could not start. See README-FIRST.txt.",
      );
    }
  }
  const aria = Deno.env.get("YTMAX_ARIA2") === "1";
  const rl = createInterface({
    input: stdin,
    crlfDelay: Infinity,
    terminal: false,
  });
  const lines = rl[Symbol.asyncIterator]();
  async function ask(label: string) {
    stdout.write(label);
    const line = await lines.next();
    return line.done ? null : line.value;
  }
  async function choose(labels: string[], fallback: number) {
    labels.forEach((label, i) => console.log(`  ${i + 1}) ${label}`));
    for (;;) {
      const raw = await ask(`Choose [${fallback + 1}]: `);
      if (raw === null) return null;
      if (raw === "") return fallback;
      const i = Number(raw) - 1;
      if (/^\d+$/.test(raw) && i >= 0 && i < labels.length) return i;
      console.log("Choose one of the numbers above.");
    }
  }
  let status = 0;
  try {
    for (;;) {
      const input = await ask(
        "\nYouTube URL (Enter to quit, U for update guidance) > ",
      );
      if (input === null || input === "") return status;
      if (input.toLowerCase() === "u") {
        console.log(
          "Update the tools using their original installers or package manager.",
        );
        continue;
      }
      const id = videoId(input);
      if (!id) {
        console.log("Use a full HTTPS link to a single YouTube video.");
        continue;
      }
      const list = await ask("Show available formats first? [y/N] ");
      if (list === null) return 130;
      if (/^y(es)?$/i.test(list)) {
        const listed = await yt([
          ...common,
          "-F",
          "--",
          "https://www.youtube.com/watch?v=" + id,
        ]);
        if (!listed.success) console.error("Could not list formats.");
      }
      console.log("Output format");
      const p = await choose([
        "MKV / original codecs",
        "MP4 / H.264 + AAC",
        "MP4 / original codecs",
        "Audio / M4A",
      ], 0);
      if (p === null) return 130;
      let cap = 0;
      if (p !== 3) {
        console.log("Maximum source height");
        const q = await choose(
          caps.map((n) => n ? n + "p" : "Maximum available"),
          0,
        );
        if (q === null) return 130;
        cap = caps[q];
      }
      console.log("Download speed");
      const speed = await choose([
        "Balanced / 4 fragments",
        "Fast / 8 fragments",
        aria
          ? "Turbo / 16 fragments + aria2c for direct HTTP"
          : "Turbo / 16 fragments",
      ], 1);
      if (speed === null) return 130;
      const result = await download(folder, id, settings(p, cap, speed, aria));
      if (result) {
        status = result;
        continue;
      }
      if (
        Deno.stdin.isTerminal() &&
        (await Deno.permissions.query({ name: "run", command: "explorer.exe" }))
            .state === "granted" &&
        /^y(es)?$/i.test(await ask("Open the folder in Explorer? [y/N] ") ?? "")
      ) {
        new Deno.Command("explorer.exe", { args: [folder] }).spawn().unref();
      }
    }
  } finally {
    rl.close();
  }
}

if (import.meta.main) {
  try {
    Deno.exitCode = await main();
  } catch (e) {
    console.error(e instanceof Error ? e.message : e);
    Deno.exitCode = 1;
  }
}
