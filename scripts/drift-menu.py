#!/usr/bin/env python3
"""drift-menu.py — Textual control menu for the drift quotient assessor.

Mutates per-session control state ONLY via drift-control.sh.
Reads score history from ~/.claude/state/drift/<sid>.jsonl.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Footer, Header, Label, Static

HOME = Path(os.path.expanduser("~"))
STATE_DIR = HOME / ".claude" / "state" / "drift"
CONTROL_SH = HOME / ".claude" / "scripts" / "drift-control.sh"
RUBRIC = HOME / ".claude" / "scripts" / "drift-rubric.md"
PROVIDERS = ["groq", "gemini", "openai", "ollama", "auto"]


def resolve_session(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    if CONTROL_SH.exists():
        try:
            out = subprocess.run(
                ["bash", str(CONTROL_SH), "-R"],
                capture_output=True, text=True, timeout=5,
            )
            sid = out.stdout.strip()
            if sid:
                return sid
        except Exception:
            pass
    try:
        files = sorted(STATE_DIR.glob("*.jsonl"),
                       key=lambda p: p.stat().st_mtime, reverse=True)
        if files:
            return files[0].stem
    except Exception:
        pass
    return None


def control_get(sid: str) -> dict:
    default = {"paused": False, "force_provider": None, "updated_at": None}
    if CONTROL_SH.exists():
        try:
            out = subprocess.run(
                ["bash", str(CONTROL_SH), "-s", sid, "-g"],
                capture_output=True, text=True, timeout=5,
            )
            return {**default, **json.loads(out.stdout)}
        except Exception:
            pass
    # fallback: read file directly
    f = STATE_DIR / f"{sid}.control.json"
    if f.is_file():
        try:
            return {**default, **json.loads(f.read_text())}
        except Exception:
            return default
    return default


def control_set(sid: str, *flags: str) -> None:
    if not CONTROL_SH.exists():
        return
    try:
        subprocess.run(
            ["bash", str(CONTROL_SH), "-s", sid, *flags],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        pass


def read_history(sid: str, n: int = 10) -> list[dict]:
    f = STATE_DIR / f"{sid}.jsonl"
    if not f.is_file():
        return []
    scores: list[dict] = []
    try:
        for line in f.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("kind") == "score":
                scores.append(obj)
    except Exception:
        return []
    return scores[-n:]


class DriftMenu(App):
    CSS = """
    Screen { align: center top; }
    #state { padding: 1 2; border: round $accent; margin: 1 2; }
    #actions { height: auto; padding: 0 2; }
    .row { height: auto; padding: 1 0; }
    Button { margin: 0 1; }
    #history { border: round $primary; margin: 1 2; padding: 0 1; height: 1fr; }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("escape", "quit", "Quit"),
        ("p", "toggle_pause", "Pause/Resume"),
        ("e", "edit_rubric", "Edit rubric"),
        ("r", "refresh", "Refresh"),
    ]

    def __init__(self, sid: str) -> None:
        super().__init__()
        self.sid = sid

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(id="state")
        with Vertical(id="actions"):
            with Horizontal(classes="row"):
                yield Label("Force provider: ")
                for p in PROVIDERS:
                    yield Button(p, id=f"prov-{p}")
            with Horizontal(classes="row"):
                yield Button("Pause/Resume", id="toggle", variant="warning")
                yield Button("Edit rubric", id="rubric")
                yield Button("Refresh", id="refresh")
        yield VerticalScroll(Static(id="historybody"), id="history")
        yield Footer()

    def on_mount(self) -> None:
        self.refresh_state()

    def refresh_state(self) -> None:
        ctrl = control_get(self.sid)
        paused = ctrl.get("paused")
        fp = ctrl.get("force_provider") or "auto"
        upd = ctrl.get("updated_at") or "—"
        self.query_one("#state", Static).update(
            f"[b]session[/b]  {self.sid}\n"
            f"[b]paused[/b]   {'YES' if paused else 'no'}\n"
            f"[b]provider[/b] {fp}   [dim](updated {upd})[/dim]"
        )
        rows = read_history(self.sid)
        if rows:
            lines = []
            for r in rows:
                ts = (r.get("ts") or "").replace("T", " ").replace("Z", "")
                lines.append(
                    f"{ts}  {r.get('score', '?')}/100  "
                    f"({r.get('tag', '?')})  [{r.get('provider', '?')}]"
                )
            body = "\n".join(lines)
        else:
            body = "(no score history yet)"
        self.query_one("#historybody", Static).update(body)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id or ""
        if bid.startswith("prov-"):
            control_set(self.sid, "--set-provider", bid[len("prov-"):])
            self.refresh_state()
        elif bid == "toggle":
            self.action_toggle_pause()
        elif bid == "rubric":
            self.action_edit_rubric()
        elif bid == "refresh":
            self.refresh_state()

    def action_refresh(self) -> None:
        self.refresh_state()

    def action_toggle_pause(self) -> None:
        ctrl = control_get(self.sid)
        new = "false" if ctrl.get("paused") else "true"
        control_set(self.sid, "--set-paused", new)
        self.refresh_state()

    def action_edit_rubric(self) -> None:
        editor = os.environ.get("EDITOR", "nano")
        with self.suspend():
            subprocess.run([editor, str(RUBRIC)])
        self.refresh_state()


def main() -> int:
    ap = argparse.ArgumentParser(description="Drift quotient control menu.")
    ap.add_argument("-s", "--session-id", default=None)
    args = ap.parse_args()
    sid = resolve_session(args.session_id)
    if not sid:
        print(f"drift-menu: no drift session found in {STATE_DIR}")
        return 1
    DriftMenu(sid).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
