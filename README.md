# prepush — 푸시 전 찬반 리뷰

push 하기 전에 Claude 세션들이 코드를 리뷰하고, **토론에서 살아남은 지적만** 자동으로 고치는 Claude Code 스킬(`/prepush`)과 스크립트.

- 찾기는 Claude Code 기본 스킬 `code-review` 가 한다 — 버그와 코드 품질을 같이 본다.
- 찾은 것을 바로 고치지 않는다. **반대파(공격)와 찬성파(방어)가 근거로 다투고**, 한쪽이 질 때까지 간 뒤에 고친다.
- 모든 단계가 `claude -p` 로 띄운 **새 세션**이라, 코드를 쓴 세션의 맥락(자기 코드 편향)이 섞이지 않는다. 세션끼리는 파일로만 주고받는다.
- 통과한 커밋만 push 되게 막는 pre-push 훅이 같이 들어 있다.

## 흐름

```
 ① 찾기        기본 스킬 code-review (고치기 없이) 가 후보를 넓게 찾음            읽기 전용
 ② 반대파      후보를 코드 + 프로젝트 기준으로 확인해 문제(C-) · 설계 지적(Q-) 으로 올림
 ③ 찬성파      각 지적에 ACCEPT(인정) / REBUT(근거로 반박)
 ④ 반대파      반박된 항목에 WITHDRAW(철회) / MAINTAIN(새 근거로 유지)
 ⑤ 찬성파      유지된 항목에 다시 판정                     … ④⑤ 최대 2번
 ⑥ 수정 담당    인정된 항목(C- · Q-)만 수정 → 자동 커밋 fix(review): …
 ⑦ 새 세션들이 방금 고친 diff 만 다시 확인                  … 최대 3라운드 (마지막은 확인만)
```

기본 스킬은 「찾기 → 바로 고치기」를 한 번에 한다(`code-review --fix` · `simplify`). 여기서는 둘을 떼어 그 사이에 토론을 둔다.

| 스킬의 부분 | 여기서 쓰는 곳 |
|---|---|
| 찾기 — `code-review` 의 버그 3관점 + 품질 4관점(재사용 · 단순화 · 효율 · 깊이, `simplify` 와 같은 관점) + `CLAUDE.md` 규칙 | ① 찾기 세션이 스킬을 `--fix` 없이 그대로 호출 |
| 고치기 — `code-review --fix` · `simplify` 의 적용 단계 | ⑥ 수정 담당. 스킬에는 「이 목록만 고치기」 호출이 없어서, 그 규칙을 `prompts/fixer.md` 에 옮겨 적고 토론에서 확정된 목록에만 적용 |

## 필요한 것

- git, bash 4.4 이상 (Windows 는 Git Bash)
- Claude Code CLI — `claude` 가 PATH 에 있어야 하고, 기본 스킬 `code-review` 가 들어 있는 버전 (2.1.322 에서 확인)

## 설치

이 폴더(내려받은 `prepush-review/`)에서:

```bash
bash install.sh /path/to/내-저장소
```

대상 저장소에 아래가 들어간다.

| 파일 | 역할 |
|---|---|
| `scripts/review/prepush.sh` | 파이프라인 본체 |
| `scripts/review/prompts/*.md` | 역할별 지시문 (찾기 · 반대파 · 찬성파 · 재반박 · 수정) |
| `scripts/review/review.conf` | **프로젝트 설정** — 기준 브랜치 · 소스 경로 |
| `scripts/review/project.md` | **프로젝트 기준** — 기준 문서 · 찾을 것 · 문제로 보지 말 것 · 수정 규칙 |
| `scripts/review/install.sh` | pre-push 훅 설치 (팀원마다 한 번) |
| `scripts/review/README.md` | 이 문서 |
| `.claude/skills/prepush/SKILL.md` | Claude Code 스킬 `/prepush` |
| `.githooks/pre-push` | 통과한 커밋만 push 허용하는 훅 원본 |

`.gitignore` 에 `.review/`, `.gitattributes` 에 셸 스크립트 LF 고정이 추가되고, 이 PC 의 pre-push 훅이 설치된다.
다시 실행하면 스크립트 · 프롬프트 · 스킬만 새 것으로 바뀌고 `review.conf` · `project.md` 는 그대로 남는다.

### 설치 뒤 할 일

1. **`scripts/review/review.conf`** — `REVIEW_BASE`(작업 브랜치가 PR 로 들어가는 브랜치)와 `REVIEW_PATHS`(리뷰할 소스 폴더)를 고친다. 경로가 없으면 파이프라인이 시작하지 않는다.
2. **`scripts/review/project.md`** — 네 절을 채운다. 리뷰 세션은 이 프로젝트를 처음 보므로 여기 적지 않은 것은 모른다. 비워 둬도 돌지만 의도된 동작이 버그로 보고된다.
3. **`.claude/settings.json`** 의 `permissions.deny` 에 아래를 더한다 — Claude 작성 세션이 게이트를 우회하거나 리뷰 결과를 고치지 못하게.
   ```json
   "Bash(git push --no-verify *)",
   "Bash(SKIP_REVIEW=1 *)",
   "Bash(bash scripts/review/prepush.sh --accept *)",
   "Bash(bash scripts/review/prepush.sh --accept)",
   "Edit(.review/**)"
   ```
4. 커밋한다. 팀원은 받은 뒤 각자 한 번 `bash scripts/review/install.sh` (git 훅은 저장소에 같이 올라가지 않는다 — **설치한 사람만** push 가 리뷰 통과를 요구받는다).

## 사용

Claude Code 에서 `/prepush`, 또는 터미널(Git Bash)에서 직접:

```bash
# 푸시 전 (작업 브랜치에서) — 기준 브랜치 이후 바뀐 코드
bash scripts/review/prepush.sh                       # 리뷰 → 수정 → 통과 시 push
bash scripts/review/prepush.sh origin feature/xxx    # 나머지 인자는 git push 로 넘어감
bash scripts/review/prepush.sh --no-push             # push 는 직접
bash scripts/review/prepush.sh --accept              # UNRESOLVED 를 사람이 확인하고 그대로 승인
SKIP_REVIEW=1 git push                               # 긴급 우회 (사람만)

# 이미 있는 코드 전체 (수정 커밋이 쌓이므로 새 브랜치에서 — 기준 브랜치에선 실행 거부)
git switch -c fix/review-full-scan origin/main
bash scripts/review/prepush.sh --all                 # REVIEW_PATHS 의 하위 폴더별로 전부
bash scripts/review/prepush.sh --all src/network     # 한 폴더만
```

| 모드 | 대상 | push |
|---|---|---|
| 푸시 전 | 기준 브랜치 이후 바뀐 코드 | 통과하면 함 (수정 커밋이 생겼으면 안 함) |
| 전체 `--all` | 이미 있는 코드 전체, 폴더별 | 안 함 |

**문서 작업은 리뷰하지 않는다** — push 하는 커밋들이 `docs/` · `*.md` 만 바꿨으면 훅이 리뷰 없이 통과시킨다.

## 결과

| 결과 | 뜻 | 다음 |
|---|---|---|
| `PASS` | 지적이 없거나 다 고쳤다 | 수정 커밋이 없으면 이미 push 됨. 있으면 **실행해서 확인한 뒤** 직접 `git push` (승인은 그 커밋에 되어 있다) |
| `UNRESOLVED` | 찬반이 끝까지 합의 못 한 문제(`C-`)가 남았다 | `unresolved.md` 를 사람이 읽고 판단. 문제없으면 `--accept` |
| `FIX_LIMIT` | 라운드 상한까지 고쳤는데 확정 문제가 남았다 | `fix-list.md` 를 보고 직접 고친다 |
| `FIX_FAILED` | 수정 세션이 아무것도 못 고쳤거나 새 파일을 만들었다 | `fix.md` · 경고를 본다 |

결과 파일은 `.review/latest/` 에 남는다.

| 파일 | 내용 |
|---|---|
| `report.md` | 최종 결과 요약 (`--all` 이면 `summary.md` 와 폴더별 `report.md`) |
| `roundN/candidates.md` | 기본 스킬 `code-review` 가 찾은 후보 원문 (JSON) |
| `roundN/con-review.md` | 반대파 지적 원문 — 후보 중 올린 것 · 올리지 않은 것과 이유 |
| `roundN/debate.md` | 찬반 공방 전체 |
| `roundN/fix-list.md` | 확정되어 수정 담당에게 넘긴 항목 (`C-` · `Q-`) |
| `roundN/fix.md` | 수정 담당이 무엇을 바꿨는지 · 무엇을 건너뛰었는지 |
| `roundN/unresolved.md` | 합의 안 된 쟁점 (`C-`) |
| `roundN/quality.md` | 설계 권고 — 고치지 않은 `Q-`. 고칠지는 사람이 정한다 |
| `roundN/prior.md` | 그 라운드 세션에 넘긴 앞 라운드 기록 |
| `withdrawn.md` | 라운드마다 철회된 지적 |

## 판정 규칙

- 찬성파가 **반박하지 않은** 지적 = 확정 → 수정 대상
- 반대파가 **철회(WITHDRAW)한** 지적만 철회 — 판정 줄을 빠뜨린 지적은 유지로 본다
- 상한까지 공방이 이어진 지적 = 합의 안 됨 → 사람 몫
- 반박 · 유지는 코드 위치나 문서 근거가 있어야 한다 (추측은 근거로 인정 안 됨)
- **문제(`C-`)** — 실제로 깨지는 실행 경로가 있거나 문서 규칙을 어긴 것. push 를 막는다
- **설계 지적(`Q-`)** — 버그가 아니라 코드가 잘 짜였는지: 재사용(이미 있는 것을 다시 만듦) · 단순화(중복 상태 · 복붙 · 깊은 중첩 · 죽은 코드) · 효율(낭비되는 일) · 깊이(증상만 덮은 임시방편). 공방을 똑같이 거치고, 살아남으면 `C-` 와 같이 고친다. 동작을 바꾸지 않고 리뷰한 코드 근처에서 끝나는 정리만 대상이다
- `Q-` 는 **push 를 막지 않는다.** 합의하지 못한 것, 수정 담당이 건너뛴 것, 마지막 라운드(확인만)에 확정된 것은 고치지 않고 `quality.md` 권고로 사람에게 넘긴다
- 2라운드부터는 **방금 고친 diff 만** 본다 — 고친 지적이 실제로 해결됐나, 수정이 새 문제를 만들었나. 처음부터 다시 보면 새 세션이 라운드마다 새 지적을 찾아 끝나지 않는다
- 출력 형식이 깨지면(찾기 결과가 스킬의 JSON 배열이 아님, 지적 블록도 `NO_FINDINGS` 도 없음, 판정 줄이 하나도 없음) 통과로 넘기지 않고 멈춘다

## 설정

`scripts/review/review.conf` 에 적는다. 같은 이름의 환경변수를 주면 그 값이 이긴다 (`REVIEW_LEVEL=medium bash scripts/review/prepush.sh`).

| 변수 | 기본값 | 설명 |
|---|---|---|
| `REVIEW_BASE` | `origin/main` | 비교 기준 브랜치 |
| `REVIEW_PATHS` | `src` | 리뷰할 경로 (쉼표 구분) |
| `REVIEW_EXCLUDE` | 없음 | 리뷰 · 수정 커밋에서 뺄 파일 glob (쉼표 구분). 예: `**/*.meta` |
| `REVIEW_LEVEL` | `high` | 찾기 단계에서 기본 스킬 `code-review` 에 주는 강도. `high` = 관점 8개를 한 세션이 돌고 스킬 자체 검증 없이 후보를 넓게 낸다(검증은 찬반이 한다). 다른 강도는 관점 구성이 달라질 수 있다 — 바꾸면 `candidates.md` 로 확인 |
| `REVIEW_MAX_ROUNDS` | `3` | 리뷰 라운드 수 (마지막은 확인만) |
| `REVIEW_DEBATE_ROUNDS` | `2` | 재반박을 주고받는 상한 |
| `REVIEW_COMPILE_CMD` | 없음 | 수정 직후 실행할 확인 명령 (빌드 · 테스트). 실패하면 수정 세션의 변경을 stash 에 보관하고 멈춘다 |
| `REVIEW_CON_MODEL` / `REVIEW_PRO_MODEL` / `REVIEW_FIX_MODEL` | 기본 모델 | 역할별 모델 (찾기는 반대파 모델을 쓴다). 찬반을 다른 모델로 두면 맹점이 덜 겹친다 |
| `REVIEW_PROJECT_FILE` | `scripts/review/project.md` | 프로젝트 기준 문서 위치 |

## 안전장치

- 찾기 · 리뷰 세션은 **읽기 전용**(Read · Grep · Glob, 찾기는 여기에 스킬 `code-review` 호출만 더함). 리뷰하다가 코드를 고칠 수 없다
- 수정 세션은 Bash 금지, 새 파일 생성 금지(만들면 멈춤). 커밋은 **리뷰 경로 안에서 바뀐 추적 파일만** — `git add -A` · 전체 stash 를 하지 않으므로 같은 폴더의 다른 작업이 섞이지 않는다
- 수정 커밋은 아직 아무도 실행해 보지 않은 코드라 자동 push 하지 않는다 (`--accept` 도 같다)
- 승인은 **커밋 해시 단위**. 리뷰 뒤 한 줄이라도 커밋하면 다시 리뷰해야 push 된다
- 리뷰 경로에 커밋 안 된 변경이 있으면 시작하지 않는다 (수정 세션의 변경과 섞이지 않게). 경로 밖 변경은 그대로 두고 돈다
- `--all` 은 기준 브랜치(main · master · develop · `REVIEW_BASE`)에서 실행을 거부한다

## 주의

- **시간 · 비용**: 라운드당 세션 3~8개를 순서대로 띄운다. 작은 변경(파일 1개) 한 판에 약 5분, 찾기 세션은 코드 양에 따라 길어진다(파일 28개짜리 폴더 하나에 찾기만 약 11분). `--all` 은 폴더 수만큼 반복한다
- **기본 스킬 버전**: 찾기는 설치된 Claude Code 의 `code-review` 스킬을 그대로 쓴다. Claude Code 를 올리면 찾는 관점 · 결과 형식이 바뀔 수 있다 — 찾기 결과가 JSON 배열이 아니면 파이프라인이 멈추므로, 그때 `prompts/find.md` 를 맞춘다
- **Windows**: Git Bash 에서 실행한다. 스크립트 줄바꿈은 LF 여야 한다 (`.gitattributes` 가 고정)
- **재귀 방지**: 파이프라인은 `REVIEW_PIPELINE=1` 을 설정한다. Stop hook 등에서 이 값이 있으면 건너뛰게 한다
- **프로젝트 hook**: 수정 세션도 Claude Code 세션이라 저장소의 `.claude/` hook · 권한 설정이 그대로 적용된다
- 오탐이 나오면 `project.md` 3절 「문제로 보지 말 것」에 한 줄 더한다
- `--all` 은 한 번에 1라운드에서 올라온 것(문제 최대 10건 · 설계 지적 최대 5건)까지만 고친다. 더 찾으려면 고친 뒤 다시 돌린다

## 프롬프트를 고칠 때

`scripts/review/prompts/` 의 파일은 `{{이름}}` 자리에 스크립트가 값을 넣어 세션에 넘긴다. 스크립트가 세션 출력에서 읽는 형식은 바꾸면 안 된다.

| 형식 | 쓰는 곳 |
|---|---|
| JSON 배열 (`"file": …` 또는 `[]`), 실패 시 `SKILL_FAILED` | 찾기 |
| `### C-01 …` · `### Q-01 …` 제목 줄, 지적 없으면 `NO_FINDINGS` | 반대파 |
| `VERDICT C-01 ACCEPT` / `REBUT` | 찬성파 |
| `VERDICT C-01 WITHDRAW` / `MAINTAIN` | 반대파 재반박 |
| `FIXED C-01: …` / `SKIPPED C-01: …` | 수정 담당 |

## 라이선스

[MIT](LICENSE)
