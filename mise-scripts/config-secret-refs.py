#!/usr/bin/env python3
"""Assert that credential-shaped config values are REFERENCES, never literals.

Every other secret gate in this repo is a pattern match: it asks "does this look
like a secret". That question has now been answered wrongly twice — a UniFi
controller password sat in an MCP `env` block in `opencode.json` for 15 months
because it was a JSON string and every rule wanted the word `export`.

This asks the opposite, structural question: for a value whose KEY says
credential, is it written as a reference to somewhere a secret actually lives?

    "UNIFI_NETWORK_PASSWORD": "${UNIFI_NETWORK_PASSWORD}"   ok
    "apiKey":                 "!printenv PI_API_KEY"        ok
    "token":                  "op://homelab/unifi/password" ok
    "password":               "hunter2"                     REJECTED

The difference matters: a pattern match can be defeated by a credential that
happens to look ordinary — short, lowercase, low entropy — which is exactly what
a human-chosen device password looks like. A structural rule cannot, because it
never reasons about the value's content at all.

Never prints a value. A finding names the file, the line and the key, which is
enough to fix it; printing the literal would copy a live credential into a
terminal, a CI log or a bug report. Same discipline as no-local-values.sh --all.

Modes:
  (default)  tracked repo content, via `git ls-files` — the gate
  --live     this machine's agent configs, which are untracked by design — the
             audit. Nothing here can be committed, but it is where the real
             credentials sit, so it is worth being able to check.
  FILE...    scan the named files — what lefthook passes as {staged_files}, so a
             commit, a tree and a machine all go through the same code.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# A key whose name claims it holds a credential. `user`/`username` is deliberately
# absent — a username is not a secret, and demanding a reference for one would be
# noise nobody heeds.
#
# `auth(?!or)` is load-bearing: a bare `auth` matched `showAuthorIcons` in
# gh-dash's config on the first run. Author is not auth.
CRED_KEY = re.compile(r"(?i)(password|passwd|secret|token|api_?key|credential|auth(?!or))")

# A key that CONTAINS a credential word but measures or describes one rather than
# holding it. Real examples from this machine's own configs, all flagged on the
# first run: `claudeCodeFirstTokenDate` (a date), `maxTokensField` (a field name),
# `max_tokens` (a count). Checked before everything else.
MEASUREMENT_KEY = re.compile(
    r"""(?ix) .*(
        date | count | field | limit | size | length | window | budget
      | usage | expiry | expires | created | updated | timestamp | at
    )$ | ^max_?tokens$"""
)

# Keys whose CHILDREN are credential-ish BY POSITION rather than by name: an MCP
# server's env block is the shape that leaked. Position matters because a secret
# can hide behind a key the name rule would never match — `env: {"UNIFI_PW": …}`.
ENV_PARENT = {"env", "environment"}

# …but an env block also carries ordinary settings, and demanding a reference for
# a username or a hostname is how a gate teaches people to ignore it. These are
# exempt inside an env block; a credential-named key still fails even here.
NON_SECRET_ENV_KEY = re.compile(
    r"""(?ix) ^(
        user | username | login | account | email | mail
      | host | hostname | server | domain | url | uri | endpoint | base_?url
      | port | path | dir | directory | file | config | profile | region | zone
      | model | provider | version | timeout | retries | limit | format
      | level | log_?level | debug | verbose | lang | locale | tz | timezone
      | term | shell | home | editor | browser | no_?color | force_?color
      | .*_(url|uri|host|hostname|port|path|dir|file|model|region|id|name
            |user|username|login|email|account|mode|type|format|level)
    )$"""
)

# Reference forms. Anything matching one of these is a pointer at a secret store,
# an indirection, or an obvious placeholder — none of them is a credential.
REFERENCE = re.compile(
    r"""(?x)
    ^\s*$                                   # empty — nothing to leak
  | ^\$                                     # $VAR, ${VAR}, $(cmd)
  | ^!                                      # !printenv FOO — resolved by running it
  | ^(op|infisical|vault|keyring|secret)://  # secret-store URIs
  | ^<[^>]*>$                               # <fill this in>
  | ^\{\{.*\}\}$                            # {{ template }}
  | ^[A-Z][A-Z0-9_]{2,}$                    # a variable's NAME, not its value
  | ^(?i:(your|my)[\s_-]?[a-z0-9_\s-]*(key|token|secret|password)([\s_-]?here)?)$
  | ^(?i:(change|replace)[\s_-]?me|placeholder|example|redacted|todo|none|null|x{4,})$
    """
)

# Where this machine keeps agent/MCP configs. Untracked by design — a real
# credential in one of these is not a repo problem, but it is still worth seeing.
LIVE_GLOBS = (
    ".claude.json",
    ".claude/settings.json",
    ".codex/*.json",
    ".pi/agent/*.json",
    ".config/opencode/*.json",
    ".config/opencode/**/*.json",
    ".docker/mcp/config.yaml",
    ".config/dotfiles/*.json",
)

SCANNABLE = (".json", ".jsonc", ".yaml", ".yml")


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments and trailing commas, preserving string bodies.

    Written by hand rather than pulled in as a dependency: this runs in `mise run
    lint`, which must work on a bare checkout with nothing installed but the
    toolchain the repo already declares.
    """
    out, i, n = [], 0, len(text)
    in_str = in_line_comment = in_block_comment = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
                out.append(c)
        elif in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 1
            elif c == "\n":
                out.append(c)  # keep line count stable
        elif in_str:
            out.append(c)
            if c == "\\":
                if nxt:
                    out.append(nxt)
                    i += 1
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
                out.append(c)
            elif c == "/" and nxt == "/":
                in_line_comment = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block_comment = True
                i += 1
            else:
                out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def line_of(raw: str, key: str, value: str) -> int:
    """Best-effort source line for a finding. Never returns the value itself."""
    for pattern in (rf'"{re.escape(key)}"\s*:\s*"{re.escape(value)}"', rf'"{re.escape(key)}"\s*:'):
        m = re.search(pattern, raw)
        if m:
            return raw.count("\n", 0, m.start()) + 1
    return 0


def walk_json(node, raw: str, path: str, under_env: bool, findings: list) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            here = f"{path}.{key}" if path else key
            if isinstance(value, str):
                interesting = not MEASUREMENT_KEY.match(key) and (
                    CRED_KEY.search(key)
                    or (under_env and not NON_SECRET_ENV_KEY.match(key))
                )
                if interesting and not REFERENCE.match(value):
                    findings.append((line_of(raw, key, value), here))
            else:
                walk_json(value, raw, here, key in ENV_PARENT, findings)
    elif isinstance(node, list):
        for idx, item in enumerate(node):
            walk_json(item, raw, f"{path}[{idx}]", under_env, findings)


# YAML gets a line scan rather than a parser: pyyaml is not in the toolchain, and
# adding a dependency to a gate that must run on a bare checkout is a worse trade
# than accepting that this sees `key: value` pairs and not anchors or flow maps.
YAML_PAIR = re.compile(r"""^[ \t]*(?P<key>[A-Za-z0-9_.-]+)[ \t]*:[ \t]*(?P<val>.*?)[ \t]*$""")

# A YAML boolean or null scalar. Not a reference form — a NON-VALUE: it carries
# one bit, so it cannot hold a credential whatever its key is called.
#
# This closes an asymmetry, it does not relax the gate. walk_json() only ever
# inspects `isinstance(value, str)`, so a JSON `true` has always been exempt by
# construction. The YAML side is a line scanner with no parser behind it (see
# the comment above), so it could not tell `persist-credentials: false` from a
# string — and flagged it, since the key matches `credential`. That was the
# first real-world hit: GitHub's actions/checkout takes exactly that key.
#
# `no`/`off`/`null` are included because YAML parses them as booleans and null.
# A config whose credential is literally the word "no" is not a leak this gate
# is for, and treating one as a finding is how a gate teaches people to ignore
# it. A quoted "false" is still a string to YAML — but the scanner strips quotes
# before this point and cannot distinguish them, which is the documented cost of
# not carrying a parser.
YAML_NONVALUE = re.compile(r"(?i)^(true|false|yes|no|on|off|null|~)$")


def scan_yaml(raw: str, findings: list) -> None:
    for num, line in enumerate(raw.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        m = YAML_PAIR.match(line)
        if not m or MEASUREMENT_KEY.match(m.group("key")):
            continue
        if not CRED_KEY.search(m.group("key")):
            continue
        val = m.group("val")
        if val.endswith(("|", ">")):  # block scalar; the value is on later lines
            continue
        val = val.split(" #", 1)[0].strip().strip("\"'")
        if val and not REFERENCE.match(val) and not YAML_NONVALUE.match(val):
            findings.append((num, m.group("key")))


def scan(file: Path) -> list:
    try:
        raw = file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    findings: list = []
    if file.suffix in (".json", ".jsonc"):
        try:
            data = json.loads(strip_jsonc(raw))
        except json.JSONDecodeError:
            return []  # not our gate's job to police syntax; lint:json does that
        walk_json(data, raw, "", False, findings)
    else:
        scan_yaml(raw, findings)
    return findings


def tracked_files() -> list:
    out = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, text=True, check=True
    ).stdout
    return [Path(p) for p in out.split("\0") if p.endswith(SCANNABLE)]


def live_files() -> list:
    home = Path.home()
    found: list = []
    for pattern in LIVE_GLOBS:
        found.extend(p for p in home.glob(pattern) if p.is_file())
    return sorted(set(found))


def main() -> int:
    args = sys.argv[1:]
    live = "--live" in args
    # Explicit paths win over both modes, so lefthook can hand this {staged_files}
    # and the same code gates a commit, a tree and a machine.
    explicit = [Path(a) for a in args if not a.startswith("-")]
    if explicit:
        files = [p for p in explicit if p.suffix in SCANNABLE and p.is_file()]
    else:
        files = live_files() if live else tracked_files()

    total = 0
    for file in files:
        for line, key in scan(file):
            total += 1
            where = file if live else file.as_posix()
            print(f"  ✗ {where}:{line or '?'}  {key}")

    if total:
        scope = "machine config" if live else "tracked config"
        print(
            f"\n{total} {scope} value(s) look like a literal credential.\n"
            "\n"
            "A value under a credential-named key must be a REFERENCE, not the\n"
            "secret itself. Accepted forms:\n"
            "\n"
            '  "${VAR}"                     resolved from the environment\n'
            '  "!printenv VAR"              resolved by running the command\n'
            '  "op://vault/item/field"      1Password / infisical:// / vault://\n'
            '  "VAR_NAME"                   names the variable rather than holding it\n'
            '  "<fill this in>"             an example file\n'
            "\n"
            "Provision the real value through dotfiles-secrets / local.env, and keep\n"
            "the config pointing at it. See CLAUDE.md, “Secrets reach the shell”.\n"
            "\n"
            "The value is deliberately not printed above — it may be live.",
            file=sys.stderr,
        )
        return 1

    if os.environ.get("VERBOSE"):
        print(f"config-secret-refs: {len(files)} file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
