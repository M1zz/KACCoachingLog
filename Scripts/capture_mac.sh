#!/bin/zsh
# Mac App Store 스크린샷 — 꾸미지 않은 창 그대로 2880×1800 을 docs/screenshots/marketing/<언어>/mac-N-<장면>.png 에 둔다.
#   zsh Scripts/capture_mac.sh [언어 ...]   (기본 ko en)
#   - Debug 빌드가 build/mac/Build/Products/Debug/KACCoachingLog.app 에 있어야 한다(-screenshotSeed 는 DEBUG 전용).
#   - 예시 기록은 메모리 저장소에만 들어간다(KACCoachingLogApp.container) — 이 Mac 의 진짜 기록 · iCloud 는 건드리지 않는다.
#     예시가 바꾸는 설정(이름 · 자격증 · 잠금)은 찍기 전에 떠 두었다가 끝나면 되돌린다.
#   - 창이 잠깐씩 앞으로 나온다. screencapture 에 화면 기록 권한이 필요하다.
set -u
cd "$(dirname "$0")/.."
APP=build/mac/Build/Products/Debug/KACCoachingLog.app
BUNDLE=com.leeo.KACCoachingLog
WIN=build/winlist                     # 창 번호를 찾는 작은 도구 (Scripts/winlist.swift)
[[ -x $WIN ]] || { mkdir -p build; swiftc -O Scripts/winlist.swift -o $WIN; }
SCREENS=("1-detail:detail" "2-recording:recording" "3-calendar:calendar" "4-export:export")
if (( $# )); then LANGS=($@); else LANGS=(ko en); fi

BACKUP=$(mktemp -t kac-defaults)
defaults export $BUNDLE $BACKUP 2>/dev/null; had=$?
restore() { if (( had == 0 )); then defaults import $BUNDLE $BACKUP; else defaults delete $BUNDLE 2>/dev/null; fi; rm -f $BACKUP; }
trap restore EXIT

for lang in $LANGS; do
  region=$([[ $lang == ko ]] && echo ko_KR || echo en_US)
  cert=$([[ $lang == ko ]] && echo kac || echo acc)     # 한국어는 KCA, 영어는 ICF 자격증 화면
  out=docs/screenshots/marketing/$lang; mkdir -p $out
  for entry in $SCREENS; do
    name=${entry%%:*}; screen=${entry#*:}
    args=(-screenshotSeed -screenshotCert $cert -backupAudio NO -ApplePersistenceIgnoreState YES
          -AppleLanguages "($lang)" -AppleLocale $region)
    [[ -n $screen ]] && args+=(-screenshotScreen $screen)
    open -n $APP --args $args
    pid=""; for i in {1..50}; do pid=$(pgrep -nx KACCoachingLog); [[ -n $pid ]] && break; sleep 0.2; done
    [[ -z $pid ]] && { echo "  ✗ 실행 안 됨"; continue; }
    sleep 4; open $APP; sleep 1.5          # 비활성(회색) 창으로 찍히지 않게 한 번 더 앞으로
    win=$($WIN $pid | awk '$6 == 0 {print $1; exit}')
    file=$out/mac-$name.png
    screencapture -x -o -l $win $file && echo "  $file $(sips -g pixelWidth -g pixelHeight $file | awk '/pixel/{printf $2" "}')"
    kill $pid; sleep 0.8
  done
done
