#!/bin/bash
# YouTube Max Downloader v2 — macOS (Apple Silicon / Intel)
# yt-dlp + FFmpeg + Deno. Downloads videos you have permission to use.
# Quality caps, container choice, accelerated segmented downloads, safe resume.
set -uo pipefail
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

DOWNLOAD_DIR="$HOME/Movies/YouTube Downloads"
BOLD='\033[1m'; CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'

if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  BOLD=''; CYAN=''; GREEN=''; RED=''; YELLOW=''; RESET=''
fi

record_file=''
active_lock=''

cleanup() {
  if [[ -n "$record_file" ]]; then rm -f -- "$record_file"; record_file=''; fi
  if [[ -n "$active_lock" ]]; then rm -f -- "$active_lock"; active_lock=''; fi
}

pause_if_needed() {
  if [[ -t 0 ]]; then read -r -p 'Press Enter to close...' _unused || true; fi
}

banner() {
  printf "${CYAN}\n  YouTube Max Downloader  ${RESET}v2\n"
  printf '  ──────────────────────────────────────────────────────────────\n'
  printf '  Save to    ~/Movies/YouTube Downloads\n'
  printf '  Select     Output format, video quality and download speed\n\n'
}

usage() {
  printf '%s\n' 'Usage: YouTube-Max-v2.command [--help | --check | VIDEO_URL]' \
    'No arguments: interactive session. VIDEO_URL: choose settings for one video.' \
    '--check: report required and optional tools without installing anything.'
}

required_tools=(yt-dlp ffmpeg ffprobe deno)

check_requirements() {
  local missing=() packages=() answer tool
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
      if [[ "$tool" == ffprobe ]]; then
        # Homebrew provides both binaries in the ffmpeg formula.
        command -v ffmpeg >/dev/null 2>&1 && packages+=(ffmpeg)
      else
        packages+=("$tool")
      fi
    fi
  done
  (( ${#missing[@]} )) || return 0
  printf 'Missing tools: %s\n' "${missing[*]}" >&2
  printf 'Homebrew command: brew install %s\n' "${packages[*]}" >&2
  if [[ ! -t 0 ]] || ! command -v brew >/dev/null 2>&1; then return 1; fi
  read -r -p 'Install these tools with Homebrew now? [y/N] ' answer || return 1
  case "$answer" in
    y|Y|yes|YES) brew install "${packages[@]}" && tool_report ;;
    *) return 1 ;;
  esac
}

tool_report() {
  local tool status=0
  for tool in "${required_tools[@]}" aria2c; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %-8s  found\n' "$tool"
    elif [[ "$tool" == aria2c ]]; then
      printf '  %-8s  optional, absent\n' "$tool"
    else
      status=1
      printf '  %-8s  missing\n' "$tool"
    fi
  done
  return "$status"
}

# Only carry a single validated ID into yt-dlp. A playlist URL on its own
# can still expand to multiple videos even when --no-playlist is present.
youtube_id() {
  local input="$1" rest host path query id=''
  [[ "$input" == https://* && "$input" != *[[:space:][:cntrl:]]* && "$input" != *\\* ]] || return 1
  rest="${input#https://}"; host="${rest%%/*}"
  [[ "$rest" != "$host" ]] || return 1
  path="${rest#*/}"; path="${path%%#*}"
  query="${path#*\?}"; path="${path%%\?*}"
  case "$host" in
    youtu.be) id="${path%/}" ;;
    youtube.com|www.youtube.com|m.youtube.com|music.youtube.com|youtube-nocookie.com|www.youtube-nocookie.com)
      case "$path" in
        watch|watch/)
          if [[ "&$query&" =~ \&v=([A-Za-z0-9_-]{11})\& ]]; then id="${BASH_REMATCH[1]}"; fi ;;
        shorts/*|live/*|embed/*|v/*) id="${path#*/}"; id="${id%/}" ;;
      esac ;;
  esac
  [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]] || return 1
  printf '%s\n' "$id"
}

select_profile() {
  local answer
  echo
  printf "${BOLD}OUTPUT FORMAT${RESET}\n"
  echo '  1) MKV - best original quality (recommended for IINA)'
  echo '  2) MP4 - H.264 + AAC (for QuickTime; may limit quality)'
  echo '  3) MP4 - highest available quality (may not work in QuickTime)'
  echo '  4) Audio only - M4A (may convert audio when necessary)'
  while true; do
    read -r -p 'Choose [1]: ' answer || return 1
    case "${answer:-1}" in
      1) PROFILE=mkv; PROFILE_NAME='Original-MKV'; break ;;
      2) PROFILE=apple; PROFILE_NAME='Apple-MP4'; break ;;
      3) PROFILE=mp4; PROFILE_NAME='Max-MP4'; break ;;
      4) PROFILE=audio; PROFILE_NAME='Audio-M4A'; break ;;
      *) echo 'Choose 1, 2, 3 or 4.' ;;
    esac
  done
}

select_resolution() {
  local answer
  if [[ "$PROFILE" == 'audio' ]]; then
    QUALITY_LIMIT=''; QUALITY_LABEL='audio'
    return 0
  fi
  echo
  printf "${BOLD}VIDEO QUALITY (maximum source height in pixels)${RESET}\n"
  echo '  1) Maximum available (up to 8K and beyond)'
  echo '  2) 8K / 4320p'
  echo '  3) 4K / 2160p'
  echo '  4) 1440p / 2K'
  echo '  5) 1080p / Full HD'
  echo '  6) 720p / HD'
  echo '  7) 480p'
  echo '  8) 360p'
  while true; do
    read -r -p 'Choose [1]: ' answer || return 1
    case "${answer:-1}" in
      1) QUALITY_LIMIT=''; QUALITY_LABEL='max'; break ;;
      2) QUALITY_LIMIT=4320; QUALITY_LABEL='4320p'; break ;;
      3) QUALITY_LIMIT=2160; QUALITY_LABEL='2160p'; break ;;
      4) QUALITY_LIMIT=1440; QUALITY_LABEL='1440p'; break ;;
      5) QUALITY_LIMIT=1080; QUALITY_LABEL='1080p'; break ;;
      6) QUALITY_LIMIT=720; QUALITY_LABEL='720p'; break ;;
      7) QUALITY_LIMIT=480; QUALITY_LABEL='480p'; break ;;
      8) QUALITY_LIMIT=360; QUALITY_LABEL='360p'; break ;;
      *) echo 'Choose 1 through 8.' ;;
    esac
  done
}

select_speed() {
  local answer
  echo
  printf "${BOLD}DOWNLOAD SPEED${RESET}\n"
  echo '  1) Balanced - 4 simultaneous fragments'
  echo '  2) Fast - 8 simultaneous fragments (recommended)'
  echo '  3) Turbo - 16 fragments + aria2c multi-connections (when supported)'
  echo '  More connections are not always faster; Turbo can cause rate limiting.'
  while true; do
    read -r -p 'Choose [2]: ' answer || return 1
    case "${answer:-2}" in
      1) FRAGMENTS=4; TURBO=0; break ;;
      2) FRAGMENTS=8; TURBO=0; break ;;
      3) FRAGMENTS=16; TURBO=1; break ;;
      *) echo 'Choose 1, 2 or 3.' ;;
    esac
  done
}

prepare_turbo() {
  local answer
  ARIA_OPTIONS=()
  [[ "$TURBO" == 1 ]] || return 0
  if ! command -v aria2c >/dev/null 2>&1; then
    echo
    echo 'Turbo optionally uses aria2c for multi-connection HTTP downloads.'
    if [[ -t 0 ]] && command -v brew >/dev/null 2>&1; then
      read -r -p 'Install aria2 with Homebrew? [y/N] ' answer || return 1
      case "$answer" in
        y|Y|yes|YES) brew install aria2 || true ;;
      esac
    fi
  fi
  if command -v aria2c >/dev/null 2>&1; then
    # aria2c for direct HTTP, yt-dlp native handling for DASH/HLS fragments.
    ARIA_OPTIONS=(--downloader aria2c --downloader 'dash,m3u8:native'
      --downloader-args 'aria2c:-x 8 -s 8 -k 1M --max-tries=5 --retry-wait=2')
  else
    echo 'aria2c not installed. Using 16 concurrent fragments where supported.'
  fi
}

show_formats() {
  echo
  echo 'Checking available YouTube formats (read-only)...'
  yt-dlp --ignore-config --no-playlist --remote-components ejs:npm -F -- "$1"
}

run_download() {
  local url="$1" format_rule output_template result_path status
  local lock_file="$DOWNLOAD_DIR/.ytmax-locks/${url##*=}"
  local -a options
  options=(
    --ignore-config --no-playlist --no-overwrites --continue
    --remote-components ejs:npm
    --retries 10 --fragment-retries 10 --extractor-retries 3 --abort-on-unavailable-fragments
    --concurrent-fragments "$FRAGMENTS"
    --no-simulate --progress --newline --progress-delta 1
    --embed-metadata --no-embed-info-json
    -P "$DOWNLOAD_DIR"
  )

  if [[ "$PROFILE" == 'audio' ]]; then
    format_rule='ba[ext=m4a]/ba/b'
    options+=(-f "$format_rule" --extract-audio --audio-format m4a)
    output_template="%(title).160B [%(id)s] [${PROFILE_NAME}].%(ext)s"
  else
    local height_filter='' container
    if [[ -n "$QUALITY_LIMIT" ]]; then height_filter="[height<=$QUALITY_LIMIT]"; fi
    if [[ "$PROFILE" == apple ]]; then
      format_rule="bv[vcodec^=avc1]${height_filter}+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1][acodec^=mp4a]${height_filter}"
      container=mp4
    else
      format_rule="bv${height_filter}+ba/b${height_filter}"
      container="$PROFILE"
    fi
    options+=(--merge-output-format "$container" --remux-video "$container")
    options+=(-f "$format_rule")
    output_template="%(title).160B [%(id)s] [%(height)sp] [${PROFILE_NAME}].%(ext)s"
  fi

  if ((${#ARIA_OPTIONS[@]})); then options+=("${ARIA_OPTIONS[@]}"); fi

  mkdir -p "$DOWNLOAD_DIR/.ytmax-locks" || return 1
  if ! shlock -f "$lock_file" -p "$$"; then
    echo 'Could not lock this video. Check for another download or a folder permission issue.' >&2
    return 1
  fi
  active_lock="$lock_file"
  # yt-dlp may rewrite embedded metadata even with --no-overwrites. If this
  # ID/profile is already present, resolve today's exact selected filename first.
  local candidate selected ext
  case "$PROFILE" in apple|mp4) ext=mp4 ;; audio) ext=m4a ;; mkv) ext=mkv ;; esac
  result_path=''
  for candidate in "$DOWNLOAD_DIR/"*" [${url##*=}] "*"[$PROFILE_NAME].$ext"; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    selected="$(yt-dlp "${options[@]}" --simulate --quiet --no-progress \
      --print filename -o "$output_template" -- "$url")" || { status=$?; cleanup; return "$status"; }
    selected="${selected%.*}.$ext"
    if [[ "${selected%/*}" == "$DOWNLOAD_DIR" && -f "$selected" && -s "$selected" && ! -L "$selected" ]]; then
      result_path="$selected"
    elif [[ -e "$selected" || -L "$selected" ]]; then
      echo 'The output path is occupied. Check the download folder.' >&2
      cleanup; return 1
    fi
    break
  done

  status=0
  if [[ -n "$result_path" ]]; then
    echo 'Already downloaded. Keeping the existing file.'
  else
    record_file="$(mktemp "${TMPDIR:-/tmp}/ytmax.XXXXXXXX")" || { cleanup; return 1; }
    printf "\n${CYAN}Downloading: ${PROFILE_NAME} | ${QUALITY_LABEL} | ${FRAGMENTS} fragments${RESET}\n"
    printf 'Note: parallel fragments only help when the source supports them.\n\n'

    yt-dlp "${options[@]}" \
      --print-to-file 'after_move:%(filepath)s' "$record_file" \
      -o "$output_template" \
      -- "$url"
    status=$?
    IFS= read -r result_path < "$record_file" || result_path=''
  fi
  if [[ $status -eq 0 ]]; then
    if [[ -z "$result_path" || "${result_path%/*}" != "$DOWNLOAD_DIR" || ! -f "$result_path" || ! -s "$result_path" || -L "$result_path" ]]; then
      echo 'No final media file could be verified in the download folder.' >&2
      cleanup
      return 1
    fi
    printf "\n${GREEN}File ready.${RESET}\n"
    printf 'File: %s\n' "$result_path"
    if [[ -t 0 ]] && command -v open >/dev/null 2>&1; then
      open "$DOWNLOAD_DIR" >/dev/null 2>&1 || true
      if [[ -d /Applications/IINA.app || -d "$HOME/Applications/IINA.app" ]]; then
        local play_answer
        read -r -p 'Play this file in IINA now? [y/N] ' play_answer || play_answer=''
        case "$play_answer" in
          y|Y|yes|YES) open -a IINA "$result_path" || true ;;
        esac
      fi
    fi
  else
    printf "\n${RED}Download failed (code %s).${RESET}\n" "$status"
    echo 'For connection errors, try Balanced. For a missing codec, list formats or choose MKV.'
    echo 'If extraction errors persist, check your yt-dlp version.'
    echo 'Some private, restricted or inaccessible videos cannot be downloaded.'
  fi
  cleanup
  return "$status"
}

main() {
  local url='' answer video_id status=0 session_status=0 once=0
  if (( $# > 1 )); then usage >&2; return 2; fi
  if (( $# == 1 )); then
    case "$1" in
      --help|-h) usage; return 0 ;;
      --check) tool_report; return $? ;;
      *) video_id="$(youtube_id "$1")" || { usage >&2; return 2; }
         url="$1"; once=1 ;;
    esac
  fi
  banner
  if ! check_requirements; then pause_if_needed; return 1; fi
  mkdir -p "$DOWNLOAD_DIR" || { echo 'Could not create download directory.'; pause_if_needed; return 1; }
  echo 'TIP: Install IINA to play MKV: brew install --cask iina'
  if (( ! once )); then
    echo 'Paste a YouTube video link. U shows update instructions. Enter quits.'
  fi
  while true; do
    if (( ! once )); then
      printf '\n'
      IFS= read -r -p 'YouTube URL > ' url || break
      [[ -n "$url" ]] || break
      case "$url" in
        U|u) echo 'To update: brew upgrade yt-dlp ffmpeg deno (and aria2 if installed).'; continue ;;
      esac
      video_id="$(youtube_id "$url")" || { echo 'Invalid URL. Use an HTTPS link to a single YouTube video.'; continue; }
    fi
    url="https://www.youtube.com/watch?v=$video_id"
    echo
    read -r -p 'Show all available formats first? [y/N] ' answer || return 130
    case "$answer" in
      y|Y|yes|YES) show_formats "$url" || echo 'Could not list formats.' >&2 ;;
    esac
    select_profile && select_resolution && select_speed && prepare_turbo || return 130
    status=0
    run_download "$url" || status=$?
    if (( once || status >= 128 )); then return "$status"; fi
    if (( status )); then session_status=$status; fi
    printf '\nPaste another URL or press Enter to exit.\n'
  done
  printf '\nGoodbye!\n'
  return "$session_status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  main "$@"
fi
