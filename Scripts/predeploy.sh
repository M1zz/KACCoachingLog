#!/bin/sh
# 배포 전 게이트 — 여기서 실패하면 DeployBar 가 아카이브를 만들지 않는다.
#
# 다국어(.xcstrings) 검사는 DeployBar 에 내장돼 있으므로 여기서 다시 하지 않는다.
# 테스트 타깃이 없으므로 핵심 로직(작성 점검 · 엑셀 내보내기) 검사를 돌린다.
set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "🧪 핵심 로직 검사"
Scripts/verify.sh core

echo ""
echo "✅ 게이트 통과 — 배포 가능"
