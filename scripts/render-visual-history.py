#!/usr/bin/env python3
"""Render the visual-history pages from <archive>/history/log.tsv.

Pure function of the ledger: safe to re-run at any time, so recovering from a bad edit
is just re-running it. Called automatically by scripts/visual-archive.sh.

The archive lives in the notes vault, not in this repo. Its location comes from --dest
or $DOTFILES_SCREENSHOT_ARCHIVE — never hardcoded here.

Two page kinds, split so neither grows unusably large:

  SCREENSHOTS.md       top index. Images appear ONLY for epic milestones (the desktop as
                       it stood at the end of an epic) — a small, curated set. Everything
                       else is a text-only table, so the page opens fast forever.
  history/<YYYY-MM>.md month page. Every batch that month, images and clips inline.
                       Bounded by the month, so an old page never gets slower.

Pages carry the vault's standard frontmatter so they index cleanly as notes.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from collections import OrderedDict
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

GENERATED = "**Generated — do not edit by hand** (`mise run screenshots:archive`)."


def remote_url() -> str:
    """Project web URL from the origin remote, for linking refs to their MRs."""
    try:
        url = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    url = re.sub(r"^(?:git@|https://)([^:/]+)[:/]", r"https://\1/", url)
    return re.sub(r"\.git$", "", url)


REMOTE = remote_url()


def reflink(ref: str) -> str:
    m = re.fullmatch(r"mr-(\d+)", ref)
    if m and REMOTE:
        return f"[{ref}]({REMOTE}/-/merge_requests/{m.group(1)})"
    return f"`{ref}`"


def pretty(ts: str) -> str:
    return f"{ts[0:4]}-{ts[4:6]}-{ts[6:8]} {ts[9:11]}:{ts[11:13]}"


def frontmatter(note_id: str, title: str, tags: list[str], created: str) -> list[str]:
    return [
        "---",
        f"id: {note_id}",
        "type: reference",
        "status: active",
        f"title: {title}",
        f"tags: [{', '.join(tags)}]",
        f"created: {created}",
        f"updated: {date.today().isoformat()}",
        "---",
        "",
    ]


def label(surface: str, file: str) -> str:
    """Clips read as "drawer (motion)" — the still and the clip sit together under one name.

    The scene names its clip `<surface>-motion`, so drop that suffix rather than
    rendering "drawer-motion (motion)".
    """
    if not file.endswith(".gif"):
        return surface
    return f"{surface.removesuffix('-motion')} (motion)"


class Batch:
    """One `visual-archive.sh` run: same timestamp + ref, one or more surfaces."""

    def __init__(self, row: dict[str, str]):
        self.ts = row["timestamp"]
        self.ref = row["ref"]
        self.epic = row.get("epic", "")
        self.milestone = row.get("milestone", "0") == "1"
        self.title = row.get("title", "")
        self.note = row.get("note", "")
        self.images: list[tuple[str, str]] = []  # (surface, file)

    @property
    def month(self) -> str:
        return f"{self.ts[0:4]}-{self.ts[4:6]}"


def load(ledger: Path) -> list[Batch]:
    if not ledger.exists():
        return []
    batches: OrderedDict[tuple[str, str], Batch] = OrderedDict()
    with ledger.open(newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            key = (row["timestamp"], row["ref"])
            batch = batches.setdefault(key, Batch(row))
            batch.images.append((row["surface"], row["file"]))
    return sorted(batches.values(), key=lambda b: b.ts)


def render_month(hist: Path, month: str, batches: list[Batch]) -> None:
    lines = frontmatter(
        note_id=f"hyprland-dotfiles-screenshots-{month}",
        title=f"Hyprland dotfiles screenshots — {month}",
        tags=["hyprland-dotfiles", "quickshell", "screenshots", "history"],
        created=f"{month}-01",
    )
    lines += [
        f"# Hyprland dotfiles visual history — {month}",
        "",
        f"Newest first. {GENERATED}",
        "Back to [all months](../SCREENSHOTS.md).",
        "",
    ]
    for b in reversed(batches):
        lines += [f"## {pretty(b.ts)} — {reflink(b.ref)}", ""]
        if b.epic:
            lines += [f"epic **{b.epic}**" + (" — milestone" if b.milestone else ""), ""]
        if b.title:
            lines += [b.title, ""]
        if b.note:
            lines += [f"_{b.note}_", ""]
        for surface, file in b.images:
            # Month pages sit in history/, so the ledger path is already relative to them.
            name = label(surface, file)
            lines += [f"**{name}**", "", f"![{name} — {b.ts}]({file})", ""]
    (hist / f"{month}.md").write_text("\n".join(lines).rstrip() + "\n")


def render_index(dest: Path, batches: list[Batch]) -> None:
    created = (
        f"{batches[0].ts[0:4]}-{batches[0].ts[4:6]}-01" if batches else date.today().isoformat()
    )
    lines = frontmatter(
        note_id="hyprland-dotfiles-screenshots",
        title="Hyprland dotfiles screenshot history",
        tags=["hyprland-dotfiles", "quickshell", "screenshots", "history", "index"],
        created=created,
    )
    lines += [
        "# Hyprland dotfiles visual history",
        "",
        f"Visual timeline of the quickshell desktop. {GENERATED}",
        "",
        "Captures come from a headless nested compositor (`mise run screenshots`), so they",
        "can be produced unattended by a background agent with no display attached.",
        "",
        "Only **epic milestones** are shown as images here — the desktop as it stood at the",
        "end of each epic. Everything else is a text-only table linking to the month page,",
        "so this page stays fast however much history accumulates.",
        "",
        "Images live in `history/<YYYY-MM>/` as `<timestamp>-<surface>-<ref>.png` (stills)",
        "and `.gif` (motion clips), so the directory listing is itself the chronological",
        "record. `history/log.tsv` is the append-only ledger these pages are built from.",
        "",
    ]

    # --- epic milestones: the curated visual spine of the desktop ---
    milestones = [b for b in batches if b.milestone]
    lines += ["## Epic milestones", ""]
    if not milestones:
        lines += [
            "_None yet. When an epic wraps, archive its final captures with_",
            "_`mise run screenshots:archive -- --epic <epic> --milestone`._",
            "",
        ]
    for b in reversed(milestones):
        lines += [f"### {b.epic} — closed {pretty(b.ts)} ({reflink(b.ref)})", ""]
        if b.title:
            lines += [b.title, ""]
        if b.note:
            lines += [f"_{b.note}_", ""]
        for surface, file in b.images:
            name = label(surface, file)
            lines += [f"**{name}**", "", f"![{name} — {b.epic}](history/{file})", ""]

    # --- everything, by month, text only ---
    months: OrderedDict[str, list[Batch]] = OrderedDict()
    for b in batches:
        months.setdefault(b.month, []).append(b)

    lines += ["## All captures", ""]
    if not months:
        lines += ["_Nothing archived yet._", ""]
    for month in sorted(months, reverse=True):
        month_batches = months[month]
        count = sum(len(b.images) for b in month_batches)
        lines += [
            f"### [{month}](history/{month}.md) — {count} capture(s)",
            "",
            "| When | Ref | Epic | Surfaces | Title |",
            "| --- | --- | --- | --- | --- |",
        ]
        for b in reversed(month_batches):
            epic = (b.epic + (" ✅" if b.milestone else "")) if b.epic else "—"
            surfaces = ", ".join(label(s, f) for s, f in b.images)
            lines += [f"| {pretty(b.ts)} | {reflink(b.ref)} | {epic} | {surfaces} | {b.title} |"]
        lines += [""]

    (dest / "SCREENSHOTS.md").write_text("\n".join(lines).rstrip() + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--dest",
        default=os.environ.get("DOTFILES_SCREENSHOT_ARCHIVE", ""),
        help="archive root (default: $DOTFILES_SCREENSHOT_ARCHIVE)",
    )
    args = ap.parse_args()
    if not args.dest:
        sys.exit("no archive root — set $DOTFILES_SCREENSHOT_ARCHIVE or pass --dest")

    dest = Path(args.dest).expanduser().resolve()
    if not dest.is_dir():
        sys.exit(f"archive root does not exist: {dest}")

    hist = dest / "history"
    hist.mkdir(parents=True, exist_ok=True)

    batches = load(hist / "log.tsv")
    months: OrderedDict[str, list[Batch]] = OrderedDict()
    for b in batches:
        months.setdefault(b.month, []).append(b)
    for month, month_batches in months.items():
        render_month(hist, month, month_batches)
    render_index(dest, batches)
    print(f"[history] {len(batches)} batch(es) across {len(months)} month(s) rendered into {dest}")


if __name__ == "__main__":
    main()
