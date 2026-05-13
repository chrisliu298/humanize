# CLAUDE.md

This is a fork of [PolyArch/humanize](https://github.com/PolyArch/humanize) — a Claude Code plugin that runs an iterative RLCR loop (Claude implements, Codex independently reviews).

## What diverges from upstream

The only intentional divergence: the optional deep-research consult is rerouted from Gemini CLI to ChatGPT Pro Extended (GPT-5 Pro) via [gpt-pro-relay](https://github.com/chrisliu298/gpt-pro).

- Upstream `/humanize:ask-gemini` → fork `/humanize:ask-gpt-pro`
- Upstream `gemini` CLI dependency → fork's `gpt-pro-relay` dependency (reachable on `macmini` by default; override with `HUMANIZE_GPT_PRO_HOST`)
- Tool tag in monitor metadata: `gpt-pro` (was `gemini`)
- Cache file prefix: `gpt-pro-run.{cmd,out,log}` (was `gemini-run.*`)
- Monitor subcommand: `humanize monitor gpt-pro` (was `humanize monitor gemini`)

**The RLCR loop itself (ask-codex, gen-plan, refine-plan, start-rlcr-loop, the hooks, the agents) is upstream-pristine.** Do not modify it gratuitously when working in this fork — keep diffs against upstream as small as possible so rebases stay easy.

## Swap surface (files that diverge from upstream)

```
scripts/ask-gpt-pro.sh              # new wrapper (replaces ask-gemini.sh)
skills/ask-gpt-pro/SKILL.md         # new slash-command contract
scripts/lib/monitor-skill.sh        # gemini → gpt-pro labels, cache prefix, filter
scripts/humanize.sh                 # monitor subcommand swap
tests/test-gen-plan.sh              # one regex edit (dropped gemini- prefix)
README.md                           # fork preface + install + Quick Start step 5
.claude-plugin/marketplace.json     # name + owner → chrisliu298
.claude-plugin/plugin.json          # author, repository, homepage → chrisliu298
```

Anything outside this list should match upstream byte-for-byte (modulo whitespace).

<important if="you are syncing the fork with upstream">

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
```

If the merge touches any file in the swap surface above, **do not accept upstream's Gemini references** — re-apply the gpt-pro variant. Quick check after merging:

```bash
grep -rln -i "gemini" . | grep -v "^./.git" | grep -v README.md
```

The only acceptable remaining `gemini` hit is the historical mention in `README.md`'s fork preface.

</important>

<important if="you are editing ask-gpt-pro.sh">

## ask-gpt-pro.sh invariants

The wrapper preserves the upstream `ask-gemini.sh` contract so the monitor and downstream callers keep working:

- **stdout** = response text (only on success)
- **stderr** = status/debug lines (always)
- **exit 0** = success; **124** = wall-clock timeout; non-zero otherwise propagates `gpt-pro-relay`'s exit
- **Artifacts**: `.humanize/skill/<unique-id>/{input,output,metadata}.md` (project-local)
- **Cache**: `~/.cache/humanize/<sanitized-path>/skill-<unique-id>/gpt-pro-run.{cmd,out,log}`
- **Metadata frontmatter** must include `tool: gpt-pro` and `model: gpt-5-pro` so the monitor filters and labels correctly

Transport auto-detection: if `hostname -s == $HUMANIZE_GPT_PRO_HOST` (default `macmini`), call `gpt-pro-relay ask` directly (wrapped in `run_with_timeout`). Otherwise use the SSH polling pattern (Phase 1 `--no-wait` submit + Phase 2 short-session `fetch` loop with exponential backoff on 255).

When changing failure-handling, use `if cmd; then :; else EXIT_CODE=$?; fi` — **not** `if ! cmd; then EXIT_CODE=$?; fi`. The latter captures `$?` after the `!` negation, which is always 0, so failures silently exit 0.

</important>

<important if="you are editing the monitor (scripts/lib/monitor-skill.sh) or humanize.sh">

## Monitor coupling

The monitor reads `tool:` from `metadata.md` and uses it both for filtering (`--tool-filter`) and for choosing the cache-file prefix (`<tool>-run.*`). If you rename the tool tag, every reference must change in lockstep across:

- `scripts/ask-gpt-pro.sh` (the `tool:` field it writes)
- `scripts/lib/monitor-skill.sh` (filter values, title, cache prefix, `--once` label branch)
- `scripts/humanize.sh` (monitor subcommand name, help text)

</important>

## Local development

The plugin is published as the directory marketplace `chrisliu298/humanize`. The author's dotfiles install it via `~/dotfiles/scripts/install-plugins.sh` → clones to `~/.cache/dotfiles-plugins/chrisliu298__humanize/` → registers in `known_marketplaces.json` → `claude plugin install humanize@chrisliu298`.

For one-off testing on a working tree:

```bash
claude --plugin-dir /path/to/this/repo
```

## License

Inherits MIT from upstream.
