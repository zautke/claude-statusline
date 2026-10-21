---
description: Interactive drift control menu — force provider, pause/resume, view history, edit rubric. Renders in-conversation via AskUserQuestion.
allowed-tools: AskUserQuestion, Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh:*), Read, Write, Edit
disable-model-invocation: true
---

# /drift-control

In-conversation control panel for the drift-quotient assessor. Same-screen, no external window.

## Current drift control state
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh --get`

## Recent scores (this session)
!`sid=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh -R 2>/dev/null); tail -n 10 "$HOME/.claude/state/drift/$sid.jsonl" 2>/dev/null | jq -rc '{ts,score,tag,provider}' 2>/dev/null`

## Task — you are the drift control menu

Using the live state injected above (the `--get` JSON shows `paused` and `force_provider`):

1. Call **AskUserQuestion** with one question, header `Drift`, options:
   - **Force provider** — override which LLM the assessor uses
   - **Pause** *or* **Resume** — show the label that is the OPPOSITE of the current `paused`
     value above (paused=false → offer "Pause"; paused=true → offer "Resume")
   - **View history** — show the recent scores
   - **Edit rubric** — modify the scoring rubric in-conversation

2. Act on the selection:
   - **Force provider** → call AskUserQuestion again, header `Provider`, options:
     `groq` / `gemini` / `openai` / `ollama`. The auto-appended "Other" entry is the escape
     hatch: if the user types `auto` (or "clear"/"reset"), treat it as clearing the force.
     Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh --set-provider <choice|auto>`.
   - **Pause / Resume** → run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh --set-paused true`
     (for Pause) or `--set-paused false` (for Resume).
   - **View history** → restate the recent scores already injected above in a compact list,
     then offer the menu again (re-run step 1).
   - **Edit rubric** → the editable copy is `~/.claude/state/drift/rubric.md` (it survives plugin
     updates). If it does not exist, first `Read` `${CLAUDE_PLUGIN_ROOT}/scripts/drift-rubric.md` and `Write`
     its content there.
     Then `Read` it, ask the user what to change, and apply the change with `Edit`.

3. After any write, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh --get` and confirm the new state in
   one line (e.g. `paused=false, force_provider=groq`).

Notes:
- Do not invent providers; the only valid forced values are groq, gemini, openai, ollama, or auto.
- All writes go through `drift-control.sh` (atomic). Never hand-edit the control.json.
