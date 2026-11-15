#!/usr/bin/env python3
"""
폴더 안의 모든 .ogg 를 .mp3 로 변환 (ffmpeg 필요).
iOS는 OGG를 재생하지 못해서 필요해요.

사용법:
    python3 convert_ogg.py [루트폴더]
"""
import os
import subprocess
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "songs_out"
count = 0
for dirpath, _, files in os.walk(root):
    for name in files:
        if not name.lower().endswith(".ogg"):
            continue
        src = os.path.join(dirpath, name)
        dst = os.path.splitext(src)[0] + ".mp3"
        if os.path.exists(dst):
            continue
        r = subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
             "-c:a", "libmp3lame", "-q:a", "2", dst]
        )
        if r.returncode == 0:
            count += 1
            print("변환:", dst)
        else:
            print("실패:", src)
print(f"완료: {count}개 변환")
