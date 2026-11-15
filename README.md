# TaikoPersonal (개인용 태고 플레이어, iOS 네이티브)

TJA 악보를 읽어서 SpriteKit으로 그리고, 터치 판정은 터치 이벤트의 타임스탬프로 계산해요.
(웹 버전의 렉을 피하려고 DOM/JS 없이 네이티브로 만든 구조예요.)

> ⚠️ 이 코드는 제 환경에서 컴파일해 보지 못했어요(macOS/Xcode 없음).
> 첫 GitHub Actions 빌드에서 에러가 나면 로그를 그대로 붙여 주세요. 바로 고칠게요.

## 1. IPA 만들기 (Mac 없이)

1. 이 폴더를 GitHub 새 저장소(private OK)에 올리기
2. 저장소 → Actions → **Build IPA** → Run workflow
3. 끝나면 Artifacts 의 `TaikoPersonal-ipa` 다운로드 (압축 풀면 `TaikoPersonal.ipa`)
4. LiveContainer / AltStore / Sideloadly 로 설치 (서명 안 된 IPA)

Mac이 있으면: `brew install xcodegen && xcodegen generate` 후 Xcode로 열어서 실행해도 돼요.

## 2. 곡 넣기

- 곡마다 폴더 하나 (`.tja` + 음원)
- 방법 A: 파일 앱 → 이 iPad → **태고** 폴더에 복사
- 방법 B: 앱 오른쪽 위 **+** 로 폴더 가져오기
- **iOS는 OGG 재생 불가** → mp3/m4a/wav 로 변환 필요 (`tools/convert_ogg.py`, ffmpeg 필요)

### taikoapp.uk 에서 곡 받기 (PC에서)

```
python3 tools/fetch_taikoweb.py songs_out 20     # 20곡만 테스트
python3 tools/convert_ogg.py songs_out           # ogg가 있다면 mp3로
```

taiko-web 표준 API 구조를 가정한 스크립트라 사이트 구조가 다르면 실패할 수 있어요.

## 3. 조작

화면 아래 4등분: `카 | 돈 | 돈 | 카` (멀티터치). 위쪽 ✕ 나가기.
설정에서 노트 속도, 화면/판정 보정(ms), 효과음 볼륨 조절.

## 지원 / 미지원

지원: BPMCHANGE, SCROLL, MEASURE, DELAY, GOGO, BARLINE, 연타, 풍선, 큰 음표, 분기 악보(마스터 분기만)
미지원: 음수 SCROLL / HBSCROLL, 2P 악보, 곡 미리듣기, 점수 기록 저장
