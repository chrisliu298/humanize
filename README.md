# Humanize (chrisliu298 fork)

**Current Version: 1.16.0**

> Fork of [PolyArch/humanize](https://github.com/PolyArch/humanize) that
> replaces the optional Gemini research consult with `ask-gpt-pro`, which
> routes deep-reasoning questions to ChatGPT Pro Extended (GPT-5 Pro) via
> [gpt-pro-relay](https://github.com/chrisliu298/gpt-pro) on a designated
> host. The RLCR loop (Claude implements, Codex reviews) is unchanged.
>
> Derived upstream from the [GAAC (GitHub-as-a-Context)](https://github.com/SihaoLiu/gaac) project.

A Claude Code plugin that provides iterative development with independent AI review. Build with confidence through continuous feedback loops.

## What is RLCR?

**RLCR** stands for **Ralph-Loop with Codex Review**, inspired by the official ralph-loop plugin and enhanced with independent Codex review. The name also reads as **Reinforcement Learning with Code Review** -- reflecting the iterative cycle where AI-generated code is continuously refined through external review feedback.

## Core Concepts

- **Iteration over Perfection** -- Instead of expecting perfect output in one shot, Humanize leverages continuous feedback loops where issues are caught early and refined incrementally.
- **One Build + One Review** -- Claude implements, Codex independently reviews. No blind spots.
- **Ralph Loop with Swarm Mode** -- Iterative refinement continues until all acceptance criteria are met. Optionally parallelize with Agent Teams.
- **Begin with the End in Mind** -- Before the loop starts, Humanize verifies that *you* understand the plan you are about to execute. The human must remain the architect. ([Details](docs/usage.md#begin-with-the-end-in-mind))

## How It Works

<p align="center">
  <img src="docs/images/rlcr-workflow.svg" alt="RLCR Workflow" width="680"/>
</p>

The loop has two phases: **Implementation** (Claude works, Codex reviews summaries) and **Code Review** (Codex checks code quality with severity markers). Issues feed back into implementation until resolved.


## Install

```bash
# Add this fork's marketplace
/plugin marketplace add chrisliu298/humanize
# Then install humanize plugin
/plugin install humanize@chrisliu298
```

Requires:

- [codex CLI](https://github.com/openai/codex) for the RLCR review loop.
- [gpt-pro-relay](https://github.com/chrisliu298/gpt-pro) reachable on `macmini`
  (or override with `HUMANIZE_GPT_PRO_HOST`) if you want to use `ask-gpt-pro`.

See the full [Installation Guide](docs/install-for-claude.md) for prerequisites and alternative setup options.

## Quick Start

1. **Generate an idea draft** from a loose thought (optional — skip if you already have a draft):
   ```bash
   /humanize:gen-idea "add undo/redo to the editor"
   ```
   Output goes to `.humanize/ideas/<slug>-<timestamp>.md` by default. Pass a `.md` path to expand existing rough notes. `--n` controls how many parallel directions explore the idea (default 6).

2. **Generate a plan** from your draft:
   ```bash
   /humanize:gen-plan --input draft.md --output docs/plan.md
   ```

3. **Refine an annotated plan** before implementation when reviewers add comments (`CMT:` ... `ENDCMT`, `<cmt>` ... `</cmt>`, or `<comment>` ... `</comment>`):
   ```bash
   /humanize:refine-plan --input docs/plan.md
   ```

4. **Run the loop**:
   ```bash
   /humanize:start-rlcr-loop docs/plan.md
   ```

5. **Consult ChatGPT Pro Extended** for deep reasoning + web research (requires `gpt-pro-relay`):
   ```bash
   /humanize:ask-gpt-pro What are the latest best practices for X?
   ```
   Each call typically takes 5-20 minutes. The wrapper auto-detects whether to invoke `gpt-pro-relay` directly (when running on `macmini`) or via the resilient SSH polling pattern.

6. **Monitor progress (in another terminal, not inside Claude Code)**:
   ```bash
   source <path/to/humanize>/scripts/humanize.sh # Or just add it into your .bashrc or .zshrc
   humanize monitor rlcr        # RLCR loop
   humanize monitor skill       # All skill invocations (codex + gpt-pro)
   humanize monitor codex       # Codex invocations only
   humanize monitor gpt-pro     # gpt-pro invocations only
   ```

## Monitor Dashboard

<p align="center">
  <img src="docs/images/monitor.png" alt="Humanize Monitor" width="680"/>
</p>

## Documentation

- [Usage Guide](docs/usage.md) -- Commands, options, environment variables
- [Install for Claude Code](docs/install-for-claude.md) -- Full installation instructions
- [Install for Codex](docs/install-for-codex.md) -- Codex skill runtime setup
- [Install for Kimi](docs/install-for-kimi.md) -- Kimi CLI skill setup
- [Configuration](docs/usage.md#configuration) -- Shared config hierarchy and override rules
- [Bitter Lesson Workflow](docs/bitlesson.md) -- Project memory, selector routing, and delta validation

## License

MIT
