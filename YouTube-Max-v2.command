#!/bin/bash
# YouTube Max Downloader v2 — macOS (Apple Silicon / Intel)
# yt-dlp + FFmpeg + Deno. Downloads videos you have permission to use.
# Quality caps, container choice, accelerated segmented downloads, safe resume.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DOWNLOAD_DIR="$HOME/Movies/YouTube Downloads"
BOLD='\033[1m'; CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'

pause_if_needed() {
  printf '\n'
  read -r -p 'Press Enter to close...' _unused || true
}

banner() {
  printf "${CYAN}\n==================================================\n"
  printf '             YouTube Max Downloader v2\n'
  printf "==================================================${RESET}\n"
  printf 'Downloads: %s\n' "$DOWNLOAD_DIR"
  printf 'Select quality, format and download speed.\n'
}

check_requirements() {
  local missing=() program answer
  for program in yt-dlp ffmpeg deno; do
    command -v "$program" >/dev/null 2>&1 || missing+=("$program")
  done
  if ((${#missing[@]} == 0)); then return 0; fi

  printf "${YELLOW}Missing tools: %s${RESET}\n" "${missing[*]}"
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew not found. Install Homebrew from https://brew.sh and rerun.'
    return 1
  fi
  read -r -p 'Install missing tools with Homebrew now? [y/N] ' answer || return 1
  case "$answer" in
    y|Y|yes|YES) brew install "${missing[@]}" || return 1 ;;
    *) echo 'Installation cancelled.'; return 1 ;;
  esac
  for program in yt-dlp ffmpeg deno; do
    command -v "$program" >/dev/null 2>&1 || { echo "Still missing: $program"; return 1; }
  done
}

is_youtube_url() {
  # Full https URLs from common YouTube domains. A URL is always passed as one quoted argument.
  case "$1" in
    https://youtube.com/*|https://www.youtube.com/*|https://m.youtube.com/*|https://music.youtube.com/*|https://youtu.be/*|https://www.youtube-nocookie.com/*|https://youtube-nocookie.com/*)
      return 0 ;;
    *) return 1 ;;
  esac
}

select_profile() {
  local answer
  echo
  printf "${BOLD}OUTPUT FORMAT${RESET}\n"
  echo '  1) MKV - best original quality (recommended for IINA)'
  echo '  2) MP4 - H.264 + AAC (Apple/QuickTime compatible; may limit quality)'
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
  printf "${BOLD}VIDEO QUALITY (maximum allowed; best available at or below it)${RESET}\n"
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
    if command -v brew >/dev/null 2>&1; then
      read -r -p 'Install aria2 with Homebrew? [y/N] ' answer || answer=''
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
  local url="$1" format_rule output_template record_file result_path
  local -a options
  options=(
    --ignore-config --no-playlist --no-overwrites --continue
    --remote-components ejs:npm
    --retries 10 --fragment-retries 10 --extractor-retries 3
    --concurrent-fragments "$FRAGMENTS"
    --newline --progress-delta 1
    --embed-metadata
    -P "$DOWNLOAD_DIR"
  )

  if [[ "$PROFILE" == 'audio' ]]; then
    format_rule='ba[ext=m4a]/ba'
    options+=(-f "$format_rule" --extract-audio --audio-format m4a)
    output_template="%(title).160B [%(id)s] [${PROFILE_NAME}].%(ext)s"
  else
    if [[ "$PROFILE" == 'apple' ]]; then
      if [[ -n "$QUALITY_LIMIT" ]]; then
        format_rule="bv[vcodec^=avc1][height<=?${QUALITY_LIMIT}]+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1][acodec^=mp4a][height<=?${QUALITY_LIMIT}]"
      else
        format_rule='bv[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1][acodec^=mp4a]'
      fi
      options+=(--merge-output-format mp4 --remux-video mp4)
    else
      if [[ -n "$QUALITY_LIMIT" ]]; then
        format_rule="bv[height<=?${QUALITY_LIMIT}]+ba/b[height<=?${QUALITY_LIMIT}]"
      else
        format_rule='bv+ba/b'
      fi
      if [[ "$PROFILE" == 'mp4' ]]; then
        options+=(--merge-output-format mp4 --remux-video mp4)
      else
        options+=(--merge-output-format mkv --remux-video mkv)
      fi
    fi
    options+=(-f "$format_rule")
    output_template="%(title).160B [%(id)s] [%(height)sp] [${PROFILE_NAME}].%(ext)s"
  fi

  if ((${#ARIA_OPTIONS[@]})); then options+=("${ARIA_OPTIONS[@]}"); fi

  record_file="$(mktemp -t ytmax.XXXXXX)" || { echo 'Could not create temporary file'; return 1; }
  printf '\n'
  printf "${CYAN}Downloading: ${PROFILE_NAME} | ${QUALITY_LABEL} | ${FRAGMENTS} fragments${RESET}\n"
  printf 'Note: parallel fragments only help when the source supports them.\n\n'

  yt-dlp "${options[@]}" \
    --print-to-file 'after_move:%(filepath)s' "$record_file" \
    -o "$output_template" \
    -- "$url"
  local status=$?
  if [[ $status -eq 0 ]]; then
    printf "\n${GREEN}Finished successfully.${RESET}\n"
    result_path="$(tail -n 1 "$record_file" 2>/dev/null || true)"
    if [[ -n "$result_path" && -f "$result_path" ]]; then
      printf 'File: %s\n' "$result_path"
    fi
    if command -v open >/dev/null 2>&1; then
      open "$DOWNLOAD_DIR" >/dev/null 2>&1 || true
      if [[ -n "$result_path" && -f "$result_path" ]] &&
         { [[ -d '/Applications/IINA.app' ]] || [[ -d "$HOME/Applications/IINA.app" ]]; }; then
        local play_answer
        read -r -p 'Play this file in IINA now? [y/N] ' play_answer || play_answer=''
        case "$play_answer" in
          y|Y|yes|YES) open -a IINA "$result_path" || true ;;
        esac
      fi
    fi
  else
    printf "\n${RED}Download failed (code %s).${RESET}\n" "$status"
    echo 'Try Balanced speed, or change MP4 to MKV.'
    echo 'If the format is missing, try a lower resolution or run: brew upgrade yt-dlp ffmpeg deno'
    echo 'Some private, restricted or inaccessible videos cannot be downloaded.'
  fi
  rm -f "$record_file"
  return "$status"
}

main() {
  local url answer
  banner
  if ! check_requirements; then pause_if_needed; exit 1; fi
  mkdir -p "$DOWNLOAD_DIR" || { echo 'Could not create download directory.'; pause_if_needed; exit 1; }
  echo
  echo 'TIP: Install IINA to play MKV: brew install --cask iina'
  echo 'Paste a YouTube URL, enter U to show update command, or press Enter to quit.'
  while true; do
    printf '\n'
    read -r -p 'YouTube URL > ' url || break
    [[ -z "$url" ]] && break
    case "$url" in
      U|u) echo 'To update, run: brew upgrade yt-dlp ffmpeg deno aria2'; continue ;;
    esac
    if ! is_youtube_url "$url"; then
      echo 'Invalid URL. Paste a full https://youtube.com or https://youtu.be link.'
      continue
    fi
    echo
    read -r -p 'Show all available formats first? [y/N] ' answer || break
    case "$answer" in
      y|Y|yes|YES) show_formats "$url" || echo 'Could not list formats.' ;;
    esac
    select_profile || break
    select_resolution || break
    select_speed || break
    prepare_turbo
    run_download "$url" || true
    printf '\nPaste another URL or press Enter to exit.\n'
  done
  printf '\nGoodbye!\n'
}

main "$@"
