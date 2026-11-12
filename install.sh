#!/usr/bin/env bash
# 찬반 리뷰 파이프라인(/prepush)을 다른 저장소에 넣는다.
#   bash install.sh <대상 저장소 경로>
# 다시 실행하면 스크립트 · 프롬프트 · 스킬은 새 것으로 덮어쓰고, 프로젝트가 채운 파일(review.conf · project.md)은 그대로 둔다.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
[[ -n "$TARGET" ]] || { echo "사용: bash install.sh <대상 저장소 경로>" >&2; exit 1; }
cd "$TARGET" || { echo "폴더가 없습니다: $TARGET" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "git 저장소가 아닙니다: $TARGET" >&2; exit 1; }
cd "$ROOT"

# 프로젝트가 채우는 파일 — 이미 있으면 덮어쓰지 않는다
is_project_file() { [[ "$1" == "scripts/review/review.conf" || "$1" == "scripts/review/project.md" ]]; }

while IFS= read -r f; do
  if is_project_file "$f" && [[ -e "$f" ]]; then
    echo "[install] 그대로 둠  $f"
    continue
  fi
  mkdir -p "$(dirname "$f")"
  cp "$HERE/files/$f" "$f"
  echo "[install] 복사      $f"
done < <(cd "$HERE/files" && find . -type f | sed 's|^\./||' | sort)
cp "$HERE/README.md" scripts/review/README.md
echo "[install] 복사      scripts/review/README.md"

# 셸 스크립트는 LF 여야 한다 (CRLF 면 bash 가 '\r' 때문에 실패)
if ! grep -q 'review-gate' .gitattributes 2>/dev/null; then
  printf '\n# review-gate: 셸 스크립트는 LF 고정\nscripts/review/*.sh text eol=lf\nscripts/review/review.conf text eol=lf\n.githooks/* text eol=lf\n' >> .gitattributes
  echo "[install] .gitattributes 에 줄바꿈 규칙 추가"
fi

# pre-push 훅 설치 + .gitignore 에 .review/ 추가 (팀원은 각자 이 줄만 실행하면 된다)
bash scripts/review/install.sh

cat <<'EOF'

다음 할 일
  1. scripts/review/review.conf — 기준 브랜치(REVIEW_BASE)와 소스 경로(REVIEW_PATHS)를 이 저장소에 맞게 고친다
  2. scripts/review/project.md  — 기준 문서 · 찾을 것 · 문제로 보지 말 것 · 수정 규칙을 채운다
  3. .claude/settings.json 의 permissions.deny 에 아래를 더한다 (Claude 작성 세션이 게이트를 우회하지 못하게)
       "Bash(git push --no-verify *)",
       "Bash(SKIP_REVIEW=1 *)",
       "Bash(bash scripts/review/prepush.sh --accept *)",
       "Bash(bash scripts/review/prepush.sh --accept)",
       "Edit(.review/**)"
  4. 커밋한다. 팀원은 받은 뒤 각자 한 번: bash scripts/review/install.sh
  사용법: scripts/review/README.md
EOF
