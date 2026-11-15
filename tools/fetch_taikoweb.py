#!/usr/bin/env python3
"""
taiko-web 서버(taikoapp.uk)에서 악보(.tja)와 음원을 폴더별로 내려받는 스크립트.

사용법:
    python3 fetch_taikoweb.py [출력폴더] [최대곡수]

taiko-web의 일반적인 API 구조(/api/config, /api/songs, /songs/<id>/main.tja,
main.mp3|ogg)를 가정한 '최선 시도' 스크립트예요. 서버 구조가 다르면 실패할 수 있어요.
받은 폴더는 앱의 '+' 버튼 또는 파일 앱으로 넣으세요.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://taikoapp.uk"
OUT = sys.argv[1] if len(sys.argv) > 1 else "songs_out"
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
HEADERS = {"User-Agent": "Mozilla/5.0"}


def get(url, binary=False):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def safe(name):
    return re.sub(r'[\\/:*?"<>|]+', "_", name).strip()[:80] or "song"


def main():
    cfg = {}
    try:
        cfg = json.loads(get(BASE + "/api/config"))
    except Exception as e:
        print("config 조회 실패(무시):", e)

    songs_base = cfg.get("songs_baseurl") or "/songs/"
    songs_base = urllib.parse.urljoin(BASE + "/", songs_base)
    if not songs_base.endswith("/"):
        songs_base += "/"

    songs = json.loads(get(BASE + "/api/songs"))
    print(f"곡 {len(songs)}개 발견, 기준 URL: {songs_base}")
    os.makedirs(OUT, exist_ok=True)

    done = 0
    for s in songs:
        if done >= LIMIT:
            break
        if not s.get("enabled", True):
            continue
        if s.get("type", "tja") != "tja":
            continue
        sid = s["id"]
        title = str(s.get("title") or sid)
        folder = os.path.join(OUT, safe(f"{sid}_{title}"))
        if os.path.exists(os.path.join(folder, "main.tja")):
            continue

        try:
            tja = get(f"{songs_base}{sid}/main.tja", binary=True)
        except Exception as e:
            print(f"[건너뜀] {title}: 악보 실패 ({e})")
            continue

        exts = []
        if s.get("music_type"):
            exts.append(s["music_type"])
        exts += [e for e in ("mp3", "ogg") if e not in exts]
        audio, audio_ext = None, None
        for ext in exts:
            try:
                audio = get(f"{songs_base}{sid}/main.{ext}", binary=True)
                audio_ext = ext
                break
            except Exception:
                continue
        if audio is None:
            print(f"[건너뜀] {title}: 음원 없음")
            continue

        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "main.tja"), "wb") as f:
            f.write(tja)
        with open(os.path.join(folder, f"main.{audio_ext}"), "wb") as f:
            f.write(audio)
        done += 1
        print(f"[{done}] {title} ({audio_ext})")
        time.sleep(0.2)

    print("완료. ogg 파일이 있으면 convert_ogg.py 로 mp3 변환하세요.")


if __name__ == "__main__":
    main()
