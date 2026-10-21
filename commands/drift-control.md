---
description: Interactive drift control menu — force provider, pause/resume, view history, edit rubric. Renders in-conversation via AskUserQuestion.
allowed-tools: AskUserQuestion, Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh:*), PowerShell(pwsh -NoProfile -File ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.ps1:*), Read, Write, Edit
disable-model-invocation: true
---

# /drift-control

In-conversation control panel for the drift-quotient assessor. Same-screen, no external window.

## The control script (pick by host)

Every step below runs `DC <args>`, where `DC` is one of two twins with identical arguments and output:

- **Windows:** run with the **PowerShell** tool: `pwsh -NoProfile -File ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.ps1 <args>`
- **macOS / Linux:** run with the **Bash** tool: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/drift-control.sh <args>`

Never run the bash twin on Windows.

## Task — you are the drift control menu

0. Load the live state: run `DC --get` (JSON with `paused` and `force_provider`) and `DC --recent 10`
   (recent scores, one compact JSON object per line; empty when none).

1. Call **AskUserQuestion** with one question, header `Drift`, options:
   - **Force provider** — override which LLM the assessor uses
   - **Pause** *or* **Resume** — show the label that is the OPPOSITE of the current `paused`
     value (paused=false → offer "Pause"; paused=true → offer "Resume")
   - **View history** — show the recent scores
   - **Edit rubric** — modify the scoring rubric in-conversation

2. Act on the selection:
   - **Force provider** → call AskUserQuestion again, header `Provider`, options:
     `groq` / `gemini` / `openai` / `ollama`. The auto-appended "Other" entry is the escape
     hatch: if the user types `auto` (or "clear"/"reset"), treat it as clearing the force.
     Then run `DC --set-provider <choice|auto>`.
   - **Pause / Resume** → run `DC --set-paused true` (for Pause) or `DC --set-paused false` (for Resume).
   - **View history** → restate the recent scores from step 0 in a compact list, then offer the
     menu again (re-run step 1).
   - **Edit rubric** → the editable copy is `~/.claude/state/drift/rubric.md` (it survives plugin
     updates). If it does not exist, first `Read` `${CLAUDE_PLUGIN_ROOT}/scripts/drift-rubric.md` and `Write`
     its content there.
     Then `Read` it, ask the user what to change, and apply the change with `Edit`.

3. After any write, run `DC --get` and confirm the new state in one line
   (e.g. `paused=false, force_provider=groq`).

Notes:
- Do not invent providers; the only valid forced values are groq, gemini, openai, ollama, or auto.
- All writes go through the control script (atomic). Never hand-edit the control.json.
