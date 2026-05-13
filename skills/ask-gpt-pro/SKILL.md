---
name: ask-gpt-pro
description: Consult ChatGPT Pro Extended (GPT-5 Pro) as an independent expert via gpt-pro-relay. Sends a question or task to gpt-pro-relay on macmini (directly when running on macmini, over SSH otherwise) and returns a deep-reasoning response with built-in web research.
argument-hint: "[--timeout SECONDS] [question or task]"
allowed-tools: "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ask-gpt-pro.sh:*)"
---

# Ask GPT-Pro

Send a question or task to ChatGPT Pro Extended (GPT-5 Pro) and return its
response. GPT-5 Pro performs deep reasoning with built-in web research,
making this ideal for hard problems that benefit from up-to-date information
and careful thinking. Typical wall-clock per call is **5-20 minutes**.

## How to Use

Do not pass free-form user text to the shell unquoted. The question or task may contain spaces or shell metacharacters such as `(`, `)`, `;`, `#`, `*`, or `[`.

If the user only supplied a question or task, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ask-gpt-pro.sh" "$ARGUMENTS"
```

If the user supplied flags such as `--timeout`, reconstruct the command so those flags remain separate shell arguments and the remaining free-form question is passed as one quoted final argument.

Example:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ask-gpt-pro.sh" --timeout 1800 "Compare recent agentic-coding benchmarks"
```

Never run this unsafe form:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ask-gpt-pro.sh" $ARGUMENTS
```

because the shell will re-parse the question text and can fail before `ask-gpt-pro.sh` starts.

## Background Execution

Each call typically runs 5-20 minutes. Always invoke this skill with:

- `run_in_background: true`
- `timeout: 3600000` (60 min)

Wait for the completion notification. Do NOT poll output files separately — the wrapper script's polling loop is already doing that.

## Interpreting Output

- The script outputs the GPT-Pro response to **stdout** and status info to **stderr**
- Read the stdout output carefully and incorporate the response into your answer
- GPT-Pro responses are typically grounded; relay any source citations when present
- If the script exits with a non-zero code, report the error to the user

## Error Handling

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success - response is in stdout |
| 1 | Validation error (missing tool, empty question, invalid flags) or empty response |
| 124 | Timeout - the overall wall-clock deadline was hit before completion. Recover with `ssh macmini gpt-pro-relay fetch <run_id> --timeout 0` |
| Other | gpt-pro-relay process error - inspect stderr; common `reason` values: `needs_reauth`, `worker_exception`, `prompt_too_large` |

## Notes

- The response is saved to `.humanize/skill/<timestamp>/output.md` for reference
- The wrapper script auto-detects whether to call gpt-pro-relay directly (when running on the relay host, default `macmini`) or via SSH polling (everywhere else)
- Override the SSH host with `HUMANIZE_GPT_PRO_HOST=<host>` if you run gpt-pro-relay on a different machine
- Each call is a fresh ChatGPT conversation — there is no carry-over context between calls
