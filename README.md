**English** | [한국어](README.ko.md)

# prepush — adversarial review before you push

A Claude Code skill (`/prepush`) and scripts that have Claude sessions review your code before you push, and automatically fix **only the findings that survive a debate**.

- Finding is done by Claude Code's built-in `code-review` skill — it looks at both bugs and code quality.
- Findings are not fixed right away. **A con side (attack) and a pro side (defense) argue with evidence** until one side gives in, and only then is anything fixed.
- Every stage is a **fresh session** started with `claude -p`, so the context of the session that wrote the code (its bias toward its own code) never leaks in. Sessions talk to each other only through files.
- It ships with a pre-push hook that blocks any push of commits that have not passed review.

> **Note:** the prompts, script messages, and review output are written in Korean. The pipeline works the same either way, but the reports in `.review/` will be in Korean.

## Flow

```
 ① Find        built-in code-review skill (no fixing) casts a wide net for candidates   read-only
 ② Con         checks each candidate against the code + project rules, files it as a
               problem (C-) or design finding (Q-)
 ③ Pro         answers each finding with ACCEPT / REBUT (counter with evidence)
 ④ Con         on rebutted items: WITHDRAW / MAINTAIN (keep it, with new evidence)
 ⑤ Pro         rules again on maintained items                    … ④⑤ at most 2 times
 ⑥ Fixer       fixes only accepted items (C- · Q-) → auto-commit fix(review): …
 ⑦ New sessions re-check only the diff just fixed                 … at most 3 rounds (last one is check-only)
```

The built-in skills do "find → fix" in one go (`code-review --fix` · `simplify`). This project splits the two apart and puts a debate in between.

| Part of the skill | Where it is used here |
|---|---|
| Finding — `code-review`'s 3 bug angles + 4 quality angles (reuse · simplification · efficiency · altitude, the same angles as `simplify`) + `CLAUDE.md` rules | ① the find session calls the skill as-is, without `--fix` |
| Fixing — the apply step of `code-review --fix` · `simplify` | ⑥ the fixer. The skill has no "fix only this list" mode, so its rules are copied into `prompts/fixer.md` and applied only to the list settled by the debate |

## Requirements

- git, bash 4.4+ (Git Bash on Windows)
- Claude Code CLI — `claude` must be on PATH, in a version that includes the built-in `code-review` skill (verified on 2.1.322)

## Install

From this folder (the downloaded `prepush-review/`):

```bash
bash install.sh /path/to/your-repo
```

The following is added to the target repo.

| File | Role |
|---|---|
| `scripts/review/prepush.sh` | The pipeline itself |
| `scripts/review/prompts/*.md` | Per-role instructions (find · con · pro · rebuttal · fix) |
| `scripts/review/review.conf` | **Project settings** — base branch · source paths |
| `scripts/review/project.md` | **Project rules** — reference docs · what to look for · what not to flag · fix rules |
| `scripts/review/install.sh` | Installs the pre-push hook (once per team member) |
| `scripts/review/README.md` · `README.ko.md` | This document |
| `.claude/skills/prepush/SKILL.md` | Claude Code skill `/prepush` |
| `.githooks/pre-push` | Source of the hook that only allows pushing reviewed commits |

`.review/` is added to `.gitignore`, an LF rule for shell scripts is added to `.gitattributes`, and the pre-push hook is installed on this machine.
Running it again replaces only the scripts · prompts · skill; `review.conf` · `project.md` are left alone.

### After installing

1. **`scripts/review/review.conf`** — set `REVIEW_BASE` (the branch your work branch is merged into via PR) and `REVIEW_PATHS` (the source folders to review). If a path does not exist, the pipeline will not start.
2. **`scripts/review/project.md`** — fill in its four sections. The review sessions see the project for the first time, so they know nothing you don't write here. It runs if left empty, but intended behavior will get reported as bugs.
3. Add the following to `permissions.deny` in **`.claude/settings.json`** — so the Claude session writing code cannot bypass the gate or tamper with review results.
   ```json
   "Bash(git push --no-verify *)",
   "Bash(SKIP_REVIEW=1 *)",
   "Bash(bash scripts/review/prepush.sh --accept *)",
   "Bash(bash scripts/review/prepush.sh --accept)",
   "Edit(.review/**)"
   ```
4. Commit. Each team member runs `bash scripts/review/install.sh` once after pulling (git hooks are not pushed with the repo — **only people who installed it** are required to pass review to push).

## Usage

`/prepush` in Claude Code, or directly from a terminal (Git Bash):

```bash
# Before pushing (on a work branch) — code changed since the base branch
bash scripts/review/prepush.sh                       # review → fix → push if passed
bash scripts/review/prepush.sh origin feature/xxx    # remaining args are passed to git push
bash scripts/review/prepush.sh --no-push             # push yourself
bash scripts/review/prepush.sh --accept              # a human reviewed UNRESOLVED and approves as-is
SKIP_REVIEW=1 git push                               # emergency bypass (humans only)

# All existing code (fix commits pile up, so use a new branch — refused on the base branch)
git switch -c fix/review-full-scan origin/main
bash scripts/review/prepush.sh --all                 # every subfolder of REVIEW_PATHS
bash scripts/review/prepush.sh --all src/network     # a single folder
```

| Mode | Target | Push |
|---|---|---|
| Pre-push | Code changed since the base branch | Yes if passed (not if fix commits were made) |
| Full `--all` | All existing code, folder by folder | No |

**Docs-only work is not reviewed** — if the commits being pushed only touch `docs/` · `*.md`, the hook lets them through without review.

## Results

| Result | Meaning | Next |
|---|---|---|
| `PASS` | No findings, or all were fixed | If there are no fix commits, it is already pushed. If there are, **run and check it**, then `git push` yourself (the approval is on that commit) |
| `UNRESOLVED` | A problem (`C-`) remains that pro and con never agreed on | A human reads `unresolved.md` and decides. If it's fine, `--accept` |
| `FIX_LIMIT` | Fixed up to the round limit but confirmed problems remain | Read `fix-list.md` and fix them yourself |
| `FIX_FAILED` | The fix session fixed nothing, or created a new file | Check `fix.md` · the warnings |

Result files are kept in `.review/latest/`.

| File | Contents |
|---|---|
| `report.md` | Final summary (with `--all`, `summary.md` plus a `report.md` per folder) |
| `roundN/candidates.md` | Raw candidates found by the built-in `code-review` skill (JSON) |
| `roundN/con-review.md` | Raw con findings — which candidates were filed and which weren't, and why |
| `roundN/debate.md` | The full pro/con exchange |
| `roundN/fix-list.md` | Items settled and handed to the fixer (`C-` · `Q-`) |
| `roundN/fix.md` | What the fixer changed · what it skipped |
| `roundN/unresolved.md` | Unsettled disputes (`C-`) |
| `roundN/quality.md` | Design recommendations — `Q-` items not fixed. A human decides whether to fix them |
| `roundN/prior.md` | Earlier-round record passed to that round's sessions |
| `withdrawn.md` | Findings withdrawn in each round |

## Ruling rules

- A finding the pro side **did not rebut** = confirmed → to be fixed
- Only findings the con side **withdrew (WITHDRAW)** are dropped — a finding with a missing verdict line is treated as maintained
- A finding still disputed at the limit = unresolved → left to a human
- Rebuttals · maintains need a code location or a doc reference (speculation is not evidence)
- **Problem (`C-`)** — has a real execution path that breaks, or violates a documented rule. Blocks the push
- **Design finding (`Q-`)** — not a bug, but whether the code is well built: reuse (rebuilding something that exists) · simplification (redundant state · copy-paste · deep nesting · dead code) · efficiency (wasted work) · altitude (a workaround that only covers the symptom). Goes through the same debate, and if it survives it is fixed like a `C-`. Only cleanups that don't change behavior and stay near the reviewed code qualify
- `Q-` **does not block the push.** Ones that weren't agreed on, ones the fixer skipped, and ones confirmed in the last (check-only) round are not fixed but handed to a human as recommendations in `quality.md`
- From round 2 on, **only the diff just fixed** is reviewed — was the fixed finding actually resolved, did the fix introduce a new problem. Starting over each time would let fresh sessions find new findings every round and never finish
- If the output format breaks (find output is not the skill's JSON array, neither finding blocks nor `NO_FINDINGS`, no verdict lines at all), it stops instead of passing

## Configuration

Set in `scripts/review/review.conf`. An environment variable with the same name wins (`REVIEW_LEVEL=medium bash scripts/review/prepush.sh`).

| Variable | Default | Description |
|---|---|---|
| `REVIEW_BASE` | `origin/main` | Base branch to compare against |
| `REVIEW_PATHS` | `src` | Paths to review (comma-separated) |
| `REVIEW_EXCLUDE` | none | File globs excluded from review · fix commits (comma-separated). e.g. `**/*.meta` |
| `REVIEW_LEVEL` | `high` | Effort passed to the built-in `code-review` skill in the find stage. `high` = one session runs 8 angles and emits candidates broadly without the skill's own verification (pro/con does the verifying). Other levels may use a different set of angles — if you change it, check `candidates.md` |
| `REVIEW_MAX_ROUNDS` | `3` | Number of review rounds (the last is check-only) |
| `REVIEW_DEBATE_ROUNDS` | `2` | Limit on rebuttal exchanges |
| `REVIEW_COMPILE_CMD` | none | Check command run right after fixing (build · test). On failure, the fix session's changes are stashed and it stops |
| `REVIEW_CON_MODEL` / `REVIEW_PRO_MODEL` / `REVIEW_FIX_MODEL` | default model | Model per role (find uses the con model). Using different models for pro and con reduces overlapping blind spots |
| `REVIEW_PROJECT_FILE` | `scripts/review/project.md` | Location of the project rules doc |

## Safeguards

- Find · review sessions are **read-only** (Read · Grep · Glob; find additionally may only call the `code-review` skill). They cannot change code while reviewing
- The fix session has no Bash and may not create new files (it stops if it does). Commits include **only tracked files changed inside the review paths** — no `git add -A` · full stash, so other work in the same folder never gets mixed in
- Fix commits are code nobody has run yet, so they are never auto-pushed (same for `--accept`)
- Approval is **per commit hash**. Commit even one line after review and it must be reviewed again to push
- It won't start if there are uncommitted changes in the review paths (so they don't mix with the fix session's changes). Changes outside the paths are left as they are
- `--all` refuses to run on base branches (main · master · develop · `REVIEW_BASE`)

## Caveats

- **Time · cost**: each round starts 3–8 sessions in sequence. A small change (1 file) takes about 5 minutes per run; the find session grows with the amount of code (one folder of 28 files took about 11 minutes for find alone). `--all` repeats per folder
- **Built-in skill version**: find uses the installed Claude Code's `code-review` skill as-is. Upgrading Claude Code may change its angles · output format — if the find output is not a JSON array the pipeline stops, so then adjust `prompts/find.md`
- **Windows**: run it in Git Bash. Script line endings must be LF (`.gitattributes` enforces this)
- **Recursion guard**: the pipeline sets `REVIEW_PIPELINE=1`. Have Stop hooks etc. skip when it is set
- **Project hooks**: the fix session is a Claude Code session too, so the repo's `.claude/` hooks · permission settings apply to it
- If you get false positives, add a line to section 3 "What not to flag" in `project.md`
- `--all` fixes at most what came up in round 1 (up to 10 problems · 5 design findings). To find more, run it again after fixing

## Editing the prompts

Files in `scripts/review/prompts/` have `{{name}}` placeholders the script fills in before handing them to a session. Do not change the formats the script parses from session output.

| Format | Used by |
|---|---|
| JSON array (`"file": …` or `[]`), `SKILL_FAILED` on failure | Find |
| `### C-01 …` · `### Q-01 …` heading lines, `NO_FINDINGS` if none | Con |
| `VERDICT C-01 ACCEPT` / `REBUT` | Pro |
| `VERDICT C-01 WITHDRAW` / `MAINTAIN` | Con rebuttal |
| `FIXED C-01: …` / `SKIPPED C-01: …` | Fixer |

## License

[MIT](LICENSE)
