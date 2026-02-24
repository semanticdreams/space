#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-test-videos}"
mkdir -p "$OUT_DIR"

# Helpers
have_enc() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE " $1 "; }
have_mux() { ffmpeg -hide_banner -formats  2>/dev/null | grep -qE " $1 "; }

echo "Output dir: $OUT_DIR"
echo "FFmpeg: $(ffmpeg -hide_banner -version | head -n1)"

# Common sources: color bars + moving pattern, plus optional audio
V_SRC_320="testsrc2=size=320x240:rate=30"
A_SRC="sine=frequency=1000:sample_rate=48000"

# 0) Baseline: 1s, H.264, yuv420p, no audio (default sanity check)
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUT_DIR/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"

# 1) Baseline with audio: 2s (tests A/V path + timestamps)
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" \
  -f lavfi -i "$A_SRC" -t 2 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k \
  -shortest -movflags +faststart \
  "$OUT_DIR/01_baseline_h264_with_audio.mp4"

# 2) NPOT resolution (OpenGL-friendly but not power-of-two): 426x240
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=426x240:rate=30" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUT_DIR/02_npot_426x240_h264_yuv420p.mp4"

# 3) Odd resolution edge case: 321x241
# Many codecs require even dims for yuv420p, so we pad to even while keeping the "odd content" centered.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=321x241:rate=30" -t 1 \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2:(ow-iw)/2:(oh-ih)/2" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUT_DIR/03_odd_content_padded_to_even_h264.mp4"

# 4) VFR-like timestamps: generate at 60fps then drop frames irregularly and set VFR output
# This tends to produce non-uniform frame durations.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=320x240:rate=60" -t 2 \
  -vf "select='not(mod(n,5))*1+not(mod(n,7))*1',setpts=N/FRAME_RATE/TB" \
  -vsync vfr \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUT_DIR/04_vfr_select_frames_h264.mp4"

# 5) yuv444p (no chroma subsampling): catches pipelines assuming 420
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" -t 1 \
  -c:v libx264 -pix_fmt yuv444p -crf 18 -movflags +faststart \
  "$OUT_DIR/05_h264_yuv444p.mp4"

# 6) B-frames + long GOP stress (still tiny): makes reordering more likely
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" -t 2 \
  -c:v libx264 -pix_fmt yuv420p -bf 3 -g 120 -keyint_min 120 -sc_threshold 0 \
  -movflags +faststart \
  "$OUT_DIR/06_h264_bframes_longgop.mp4"

# 7) Rotation metadata (common from phone videos)
# This sets rotate tag without changing pixels; your engine may need to respect metadata (or explicitly ignore it).
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=240x320:rate=30" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -metadata:s:v:0 rotate=90 \
  -movflags +faststart \
  "$OUT_DIR/07_rotate_metadata_90deg.mp4"

# 8) 10-bit HEVC (H.265) edge case: tests pixel formats like yuv420p10le
if have_enc libx265; then
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "$V_SRC_320" -t 1 \
    -c:v libx265 -pix_fmt yuv420p10le -x265-params log-level=error \
    "$OUT_DIR/08_hevc_10bit_yuv420p10le.mp4"
else
  echo "Skipping HEVC 10-bit (libx265 not available)"
fi

# 9) VP9/WebM (different demuxer/decoder path)
if have_enc libvpx-vp9; then
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "$V_SRC_320" -t 1 \
    -c:v libvpx-vp9 -b:v 0 -crf 45 -pix_fmt yuv420p \
    "$OUT_DIR/09_vp9_webm.webm"
else
  echo "Skipping VP9/WebM (libvpx-vp9 not available)"
fi

# 10) "No B-frames, all-intra" (every frame keyframe) — good for simplest decode & seeking tests
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -g 1 -keyint_min 1 -sc_threshold 0 \
  -movflags +faststart \
  "$OUT_DIR/10_h264_all_intra.mp4"

# 11) Shortest possible file: ~0.25s (helps test your startup/shutdown edge cases)
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "$V_SRC_320" -t 0.25 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUT_DIR/11_ultra_short_250ms.mp4"

echo "Done. Generated files:"
ls -1 "$OUT_DIR"
