#!/usr/bin/env bash
# play_video_mpv_intel.sh - MPV Video Playback Wrapper for Intel Iris Pro 5200 VA-API
# Repository: nouveau_mesa_kepler_fix
# Prevents Nouveau dGPU VRAM PTE faults on channel 6 and prevents GNOME Shell crashes

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <video_file_or_youtube_url>"
    echo "Example: $0 https://www.youtube.com/watch?v=mCTEbJOnXJ4"
    exit 1
fi

TARGET="$1"

echo "========================================================================"
echo "    MPV Intel Iris Pro 5200 Hardware VA-API Video Player"
echo "========================================================================"
echo "Target: ${TARGET}"

# Force Intel i965 VA-API driver and renderD129 DRI node
export LIBVA_DRIVER_NAME=i965
export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export DRI_PRIME=pci-0000_00_02_0

exec mpv --fs --vo=gpu --hwdec=vaapi --ytdl-format="bestvideo[height<=1080]+bestaudio/best" "${TARGET}"
