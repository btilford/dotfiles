# Publish audit — `btilford/dotfiles`

Audit date: **2026-08-20**. Base commit: `3af445f` (`origin/master`).
Tooling: `git 2.55.0`, `gitleaks 8.30.1`.

> **Historical record.** The commands and file names below are reproduced as they
> were run on the audit date. On 2026-08-24 the scanner became `betterleaks` and
> the config was renamed `.betterleaks.toml` / `.betterleaksignore`, and lefthook
> was replaced by hk (`hk.pkl`). Re-run anything here with the new names; the
> flags used are unchanged. This document is deliberately not rewritten.

This document records what an audit of this repository found before publication
to a public mirror. It reports findings. It does not remove them. A committed
credential, hostname or identity is a rotate-and-purge decision for a person,
not a change to a diff. Section 7 lists every finding that is reported and left
in place on purpose.

Scope note: this repository is the reference the other repositories in the same
review round were modelled on. Most of the hardening below already existed.
Section 2 separates what was already correct from what this branch changed.

---

## 1. Method

Four scans ran. Each command below is the command that ran, and each output
block is its real output.

| Scan | Question it answers |
| --- | --- |
| full-history `gitleaks git` | did a secret ever enter any reachable commit |
| merge-diff pass | did a secret enter through a conflict resolution |
| `git archive HEAD` + `gitleaks dir` | does a secret sit in tracked content now |
| grep sweeps | is there an email, a host name or a home path in tracked text |

---

## 2. Corrections to the plan's "known gaps" list

The plan note `loop-repo-publish-hardening` carried a gap list for this
repository. Most of it was stale. Each row was checked.

| Plan claim | Reality | Evidence |
| --- | --- | --- |
| 532 tracked files | **618** at `origin/master` (617 after this branch) | `git ls-tree -r --name-only origin/master \| wc -l` |
| no LICENSE | **LICENSE exists** — MIT, 57 lines | `LICENSE:1` |
| GitHub Actions not pinned | **all 4 `uses:` pinned to 40-hex SHAs** | `lint.yml:39,54,70,77` |
| workflow permissions missing | **`permissions: contents: read` present** | `lint.yml:31-32` |
| gitleaks image on a tag | **pinned by `@sha256:` digest** | `.gitlab-ci.yml:62` |
| `.gitleaks.toml` has a `paths` allowlist | **it has none, deliberately** | `.gitleaks.toml:134-145` |
| lefthook missing a `commit-msg` hook | **both hooks present** | `lefthook.yml:43,54` |
| shellcheck coverage missing | **present on all three surfaces** | `mise.toml:197`, `.gitlab-ci.yml:41`, `lint.yml:60` |

Two consequences follow, and this document states them plainly rather than
claiming credit:

- **Gate additions 3 and 4 of the recipe (action pinning, workflow permissions)
  were already satisfied before this branch.** This branch did not add them.
- The `.gitleaks.toml` allowlist structure is already the correct narrow form:
  `targetRules` with `regexTarget = "match"`, and no `paths` key anywhere. It
  was not changed.

The plan's gap list must be treated as unverified for any repository. Four
review items in a row found it wrong.

---

## 3. Full-history secret scan

### 3.1 The scan

The `refs/spice/*` exclusion is required. git-spice keeps its stack metadata in
`refs/spice/data`, a local-only ref that no clone can reach, and its cache key
trips the `generic-api-key` rule.

```console
$ gitleaks git . --log-opts='--all --not --glob=refs/spice/*' \
    -c .gitleaks.toml --no-banner --redact
INF Unknown SCM platform. Use --platform to include links in findings.
INF 453 commits scanned.
INF scanned ~9733596 bytes (9.73 MB) in 584ms
INF no leaks found
```

**Result: clean.** Exit code 0.

### 3.2 Proof that the exclusion is necessary and harmless

Without the exclusion the same scan reports exactly one finding, and that
finding is the git-spice ref:

```console
$ gitleaks git . --log-opts='--all' -c .gitleaks.toml --no-banner --redact
INF 464 commits scanned.
WRN leaks found: 1
```

The finding, from the JSON report:

```text
RuleID : generic-api-key
File   : templates
Commit : adda08b008e6dfb811bcb4abf5bcf687185541d3
Author : git-spice  git-spice@localhost
Date   : 2026-08-21T03:58:27Z
```

The author is `git-spice@localhost`. The commit is not reachable from any
branch, tag or remote ref. It is local tool state. The exclusion removes this
and nothing else.

### 3.3 Verification that no `master` commit fell out of the scanned set

An exclusion that quietly drops real commits is worse than no scan. This is the
check that the scanned revision set is a superset of `master`:

```console
$ git rev-list master | sort > master.txt
$ git rev-list --all --not --glob='refs/spice/*' | sort > scanned.txt
$ wc -l < master.txt
566
$ wc -l < scanned.txt
568
$ comm -23 master.txt scanned.txt | wc -l
0
```

**Zero commits in `master` are absent from the scanned set.** The same check
against `origin/master` also returns 0.

### 3.4 Why gitleaks reports fewer commits than `rev-list`

`rev-list` counts 568 commits. gitleaks reports 453. The two numbers measure
different things, and the difference is not a coverage gap:

| Count | Source |
| --- | --- |
| 568 | commits in the revision set |
| 111 | of those are merge commits |
| 457 | non-merge commits |
| 453 | commits gitleaks reports as scanned |

gitleaks drives `git log -p`, which emits no patch for a merge commit by
default. Its counter therefore reports commits that produced a text patch, not
commits in the set. **The counter is not the coverage proof. Section 3.3 is.**

### 3.5 Merge commits scanned separately

Because `git log -p` skips merge diffs, content introduced only in a conflict
resolution — an "evil merge" — is invisible to the scan in 3.1. A second pass
covers it:

```console
$ gitleaks git . \
    --log-opts='--all --not --glob=refs/spice/* --diff-merges=first-parent' \
    -c .gitleaks.toml --no-banner --redact
INF 562 commits scanned.
INF scanned ~12895668 bytes (12.90 MB) in 726ms
INF no leaks found
```

**Result: clean.** 562 commits, 12.90 MB, against 453 and 9.73 MB in the
default pass. The merge diffs are real content, and they are now covered.

### 3.6 Tracked-content export scan

This is the scan that needs no path exemption, because an export contains only
tracked content. Untracked provisioned files that hold real credentials are
never seen.

```console
$ git archive HEAD | tar -x -C export/
$ find export/ -type f | wc -l
617
$ gitleaks dir export/ -c .gitleaks.toml --no-banner --redact
INF scanned ~4100660 bytes (4.10 MB) in 173ms
INF no leaks found
```

617 regular files plus one tracked symlink (`AGENTS.md`) accounts for all 618
tracked paths at `origin/master`.

**Result: clean.**

### 3.7 Note on the historical secrets

`CLAUDE.md` records that three secrets were committed here before the
public-mirror rule existed, and that `mise run audit:secrets-history` was
expected to stay red until a history rewrite removed them. **The scan above is
green.** The rewrite already happened. The custom rules that caught those
shapes — `npmrc-authtoken`, `google-app-password`, `bare-secret-export` — are
still present in `.gitleaks.toml` and must stay, because they are what makes
re-introduction detectable.

### 3.8 Commit author identity

The plan records 58 GitLab web-UI merge commits stamped with a real personal
address. That is also resolved:

```console
$ git log --format='%ae' master | sort | uniq -c
    566 248725+btilford@users.noreply.github.com
$ git log --format='%ce' master | sort | uniq -c
    566 248725+btilford@users.noreply.github.com
```

Every commit on `master`, author and committer, carries the GitHub noreply
address. No personal address remains in commit metadata.

---

## 4. Verdict on the files that match an email pattern

The handoff named three files. A sweep of all tracked content found **four**
files with a full email address, plus a fifth file with an email-shaped string
that a stricter pattern misses.

```sh
git ls-files -z | xargs -0 grep -InE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
```

The addresses themselves are **not reproduced below**. Three of them belong to
real third parties, and repeating a live personal address inside an audit does
the same thing to it that publishing the repository would. The file, the line
and the verdict are what a reader needs; the address is one `sed -n` away for
anyone who has the checkout.

| File | Line | What the match is | Verdict |
| --- | --- | --- | --- |
| `hyprland/.config/hypr/scripts/ThemeChanger.sh` | 4 | an SPDX `FileCopyrightText` header | **Third party. Not personal.** The upstream author, Ahum Maitra. See section 6. |
| `kmonad/.config/kmonad/Keycode.hs` | 7 | the `Maintainer :` field | **Third party. Not personal.** Upstream kmonad, by David Janssen. |
| `rofi/.config/rofi/themes/gruvbox-common.rasinc` | 4 | an `Author:` header | **Third party. Not personal.** Upstream `bardisty/gruvbox-rofi`. |
| `git/.config/git/profiles/anon.gitconfig` | 3 | the anon profile's `email =` | **Placeholder, intentional.** A non-existent domain, chosen to be obviously fake. |
| `docker/.docker/mcp/config.example.yaml` | 4 | an example `email_address:` | **Placeholder.** An RFC 2606 reserved domain in an example file. |

**No personal email address belonging to the repository owner is present in any
tracked file.**

### 4.0 The audit tripped the repository's own email gate

Worth recording, because it is the gate working. The first draft of the table
above spelled all five addresses out. `mise-scripts/no-local-values.sh` refused
the commit and named three lines — the three real third-party addresses — while
passing the two placeholders.

The gate was right, and the repository already states the principle: "Write
about a scrubbed string without spelling it." The table was rewritten. No
allowlist was added and no pattern was weakened.

### 4.1 The third named file, and what it actually contains

`git/.config/git/core.gitconfig` matches no full email address. It contains two
`@`-shaped strings, both in comments:

- `gitlab.example.com` (line 34) — an RFC 2606 placeholder, correct as written.
- `btilford@cachyos-fwd.(none)` (line 13) — **not an email address**, and not a
  leak of one. It is git's `user@hostname` fallback, quoted in a comment that
  explains why `user.useConfigOnly = true` is set. `(none)` is not a domain.

It does contain a machine host name. That is reported separately in section 7.

**Nothing in any of these five files was edited.**

---

## 5. Verdict on the two files the handoff called cruft

One is cruft. **One is not**, and the handoff's assumption about it is wrong.

### 5.1 `envman/.config/envman/PATH.env` — not cruft, left tracked

The file is 0 bytes, and that is its purpose. It has a README beside it that
says so:

> **The file is empty, and that is the point.** Several installers (webi and
> friends) source `~/.config/envman/PATH.env` from shell rc files and *create*
> it with their own `export PATH=...` lines on first run. Tracking an empty one
> keeps the path a repo-owned file so an installer's machine-specific PATH edit
> shows up as a diff instead of appearing out of nowhere.

Every historical version of the path is the same blob — `e69de29`, git's empty
blob. The file has never held content. Both `bash/.bashrc` and
`zsh/.config/zshrc/50-custom` reference the `envman` directory, and `README.md`
lists the package.

**Decision: leave it tracked.** Untracking it would delete a documented design
decision and turn a future installer's PATH edit back into an invisible
untracked file. It carries no risk: the blob is empty in every commit.

### 5.2 `terminator/.config/terminator/config.bak` — cruft, untracked

269 bytes. One commit only, `2c93cd6` ("Moving from nix home-manager to stow",
2024-12-14), and never updated since. The package's own README already said it
was not ours:

> `config.bak` is terminator's own backup, not ours. Nothing consumes it.

**History check before deciding.** The one and only historical blob was read in
full. It is a terminator skeleton: `[global_config]`, `[keybindings]`, an empty
default profile, a single-window layout, `[plugins]`. **No credential, no host
name, no path, no identity.** Untracking the tip therefore masks nothing —
there is nothing in history to mask.

This is the "excluded" tier from `CLAUDE.md`, section "Files the repo does not
own": the owner writes it, nothing needs a starting point.

Applied in this branch:

- `git rm --cached terminator/.config/terminator/config.bak`
- `.gitignore` entry
- new `terminator/.stow-local-ignore` (which restates `README.*`, because a
  package-local ignore file replaces stow's built-in list rather than adding to
  it)
- `terminator/README.md` updated

---

## 6. Dependency and tooling licence note

`LICENSE` is MIT. **The MIT grant does not cover everything in the tree**, and
`README.md` already says so in its "License" section, with a table naming three
bodies of vendored content. That section is accurate as far as it goes.

Verified vendored provenance:

| Content | Licence | Covered by the README table |
| --- | --- | --- |
| 30 files derived from `JaKooLit/Hyprland-Dots` | GPL-3.0 | yes (the table says 29; the count is 30) |
| `yazi/.config/yazi/flavors/{ashen,sunset}.yazi/` | MIT, own `LICENSE` files present | yes |
| `git/.config/git/templates/hooks/*.sample` | GPL-2.0 | yes |
| `hyprland/.config/hypr/scripts/ThemeChanger.sh` | **GPL-3.0-or-later**, Ahum Maitra, `TheAhumMaitra/cautious-waddle` | **no** |
| `rofi/.config/rofi/themes/gruvbox-common.rasinc` | bardisty, `bardisty/gruvbox-rofi` | **no** |
| `kmonad/.config/kmonad/Keycode.hs`, `tutorial.kbd` | MIT, David Janssen (kmonad) | **no** |

The gaps are reported, not fixed — see section 7, finding F3. Each file keeps
its upstream attribution header intact, which is the authoritative answer for
that file. GPL-3.0 content is copyleft: redistributing it, modified or not,
requires GPL-3.0 and available source. That obligation already applies to this
repository through the JaKooLit files, so `ThemeChanger.sh` adds no new class of
obligation. It does mean the README's source pointer is wrong for that file.

Tooling supply chain, checked:

- GitHub Actions: 4 of 4 pinned to full commit SHAs, with the release recorded
  in a comment beside each.
- CI container images: 5 of 5 pinned by `@sha256:` digest, with the tag
  recorded in a comment beside each.
- `mise.toml` tools: declared as `latest`. No lockfile. See finding F4.

---

## 7. Findings reported and left in place

Every item here is deliberately **not** changed. Each one is a decision for a
person.

### F1 — A machine host name appears in 8 tracked files

The string `cachyos-fwd` is a workstation host name. Under this repository's own
rule ("no private infrastructure names ... host names, LAN IPs and internal
project names are infrastructure disclosure"), it qualifies.

```console
$ git ls-files -z | xargs -0 grep -Iln 'cachyos-fwd'
commands/.local/bin/sync-litellm-models
commands/README.md
git/.config/git/core.gitconfig
hyprland/.config/hypr/hypridle.nosuspend.conf
hyprland/.config/hypr/lua/autostart.lua
hyprland/.config/hypr/scripts/Launcher.sh
mise-scripts/visuals/README.md
rofi/CLAUDE.md
```

**Assessment.** This is a LAN host name, not a routable one, and it names a
personal workstation rather than infrastructure. It is a weaker disclosure than
a server name or an IP. It is not currently in `scrub.patterns` or `local.env`,
which is why `mise run lint:private` passes.

**Not changed, for two reasons.** Removing it from 8 tracked files does not
remove it from history, so the removal would only mask it. And the decision on
whether a personal workstation name counts under the rule belongs to the person
whose workstation it is.

**Options, if a decision is wanted:** add `cachyos-fwd` to
`~/.config/dotfiles/scrub.patterns` so re-introduction is blocked going forward;
or accept it and record the acceptance in `CLAUDE.md`.

### F2 — Machine and client names in kmonad keymap file names

```text
kmonad/.config/kmonad/linux-cachyos2-built-in.kbd
kmonad/.config/kmonad/linux-cachyos2-laptop.kbd
kmonad/.config/kmonad/macos-macbook-pro-13i-2017.kbd
kmonad/.config/kmonad/macos-work-2025.kbd
```

`macos-work-2025.kbd` is the file `CLAUDE.md` records as already renamed away
from a client name, so that one is resolved. The remaining names disclose
machine identity in the same weak class as F1. Renaming a tracked file does not
remove the old name from history. **Not changed.**

### F3 — Three vendored sources are missing from the README licence table

Detailed in section 6. `ThemeChanger.sh` (GPL-3.0-or-later, Ahum Maitra), the
gruvbox rofi include (bardisty) and the kmonad files (MIT, David Janssen) are
not named. The README's JaKooLit row says "the rofi theme", but
`gruvbox-common.rasinc` does not come from JaKooLit — it carries no JaKooLit
attribution. The README's file count for the JaKooLit body says 29; the measured
count is 30.

This is an accuracy problem in an attribution notice, so **the fix belongs to
whoever can confirm each provenance**, not to an automated pass. Not changed.

### F4 — `mise.toml` declares every tool as `latest`

There is no lockfile, so a tool version is resolved at install time and nothing
records which version gated a given merge. This is the same class of problem the
repository already solved for CI images and Actions by pinning.

**Not changed**, because pinning the toolchain is a behaviour change to the lint
suite on every surface, and the handoff scope excludes dependency version bumps.
`renovate.json5` disables its `mise` manager explicitly and says why, so the
decision is recorded rather than silently deferred.

### F5 — The GitHub `lint` workflow was already failing on `master` (now fixed)

Found while verifying this branch, not caused by it. `mise run lint` failed at
`lint:lua` on unmodified content:

```text
nvim/.config/nvim/lua/plugins/nvim-lspconfig.lua:59:13: unused variable 'home'
Total: 1 warning / 0 errors in 80 files
```

Confirmed against the real workflow history rather than assumed:

```console
$ gh run list --repo btilford/dotfiles --workflow lint.yml --limit 5
completed  failure  Merge branch 'chore/lua-format-conformance' into 'master'  ...
completed  failure  Merge branch 'feat/hypr-xreal-glasses' into 'master'       ...
$ gh run view 32447434704 --repo btilford/dotfiles --log-failed
[lint:lua] Checking nvim/.config/nvim/lua/plugins/nvim-lspconfig.lua 1 warning
[lint:lua] Total: 1 warning / 0 errors in 80 files
[lint:lua] ERROR task failed
##[error]Process completed with exit code 123
```

The last two runs on `master` both failed for this one line. The GitLab
pipeline is unaffected, because its job set does not include `lint:lua`.

`local home` was dead code: its only remaining reference was inside a
commented-out `harper_ls` block. **Fixed in this branch** — the declaration is
removed and the commented block now calls `os.getenv("HOME")` inline, so
re-enabling that block restores a working configuration rather than a reference
to a variable that no longer exists.

This is outside the stated scope of a publish audit, and it is called out here
for that reason. It was fixed rather than only reported because the alternative
was to leave the repository's strictest gate red, which the acceptance criteria
for this work rule out. No lint rule was relaxed and no check was disabled to
achieve it.

---

## 8. Changes made in this branch

Additive only. No gate removed, disabled or relaxed.

| Change | File | Why |
| --- | --- | --- |
| `persist-credentials: false` on both checkouts | `.github/workflows/lint.yml` | `actions/checkout` defaults to **true** and writes the job's `GITHUB_TOKEN` into `.git/config` for the rest of the job. Nothing after checkout talks to the remote. It matters most in `secrets-live`, which hands the history to trufflehog and makes outbound calls. |
| untrack `config.bak`, add `.gitignore` and `.stow-local-ignore` entries | `terminator/` | Section 5.2. |
| `renovate.json5` added | repo root | Section 9. |
| YAML boolean handling in the secret-refs gate | `mise-scripts/config-secret-refs.py` | Section 8.1. |
| remove a dead `local home` | `nvim/.config/nvim/lua/plugins/nvim-lspconfig.lua` | Pre-existing `lint:lua` failure on `master`. See F5. |
| this document | `docs/publish-audit.md` | — |

### 8.1 A gate defect found by making the first change

Adding `persist-credentials: false` **failed `mise run lint`**:

```text
[lint:mcp-config]   ✗ .github/workflows/lint.yml:50  persist-credentials
[lint:mcp-config]   ✗ .github/workflows/lint.yml:86  persist-credentials
```

`config-secret-refs.py` asserts that a value under a credential-named key is a
reference. `persist-credentials` matches its `credential` key pattern, and
`false` is not a reference form.

This is a false positive, and it exposed an **asymmetry between the two halves
of the same gate**. `walk_json()` only inspects values where
`isinstance(value, str)`, so a JSON `true` has always been exempt by
construction. The YAML side is a line scanner with no parser behind it — a
documented trade-off, since pyyaml is not in the toolchain — so it could not
tell a boolean from a string.

The fix adds `YAML_NONVALUE`, matching `true|false|yes|no|on|off|null|~`, to the
YAML path only. **This does not weaken the gate.** A boolean carries one bit and
cannot hold a credential whatever its key is called, and the JSON path already
behaved this way. Verified against a probe file:

The probe file holds six pairs: two literal credentials, one reference, and
three booleans. The literal values are not reproduced here, because a document
that demonstrates a secret gate must not itself carry a secret-shaped string
past that gate. The keys and the outcome are what matter:

```console
$ ./mise-scripts/config-secret-refs.py probe.yml
  ✗ probe.yml:1  password        # literal value        -> still caught
  ✗ probe.yml:2  api_key         # literal value        -> still caught
exit=1
```

The three boolean pairs (`persist-credentials: false`, `credential-mode: true`,
`secret: no`) and the reference pair (`token: "${GITHUB_TOKEN}"`) produced no
finding, which is the intended result.

This document tripping the gate is itself worth recording. The first draft
spelled the probe's fake API key out in full, and `gitleaks dir .` — the exact
command the GitLab `lint:secrets` job runs — flagged it as `generic-api-key` at
this line. The gate was right: a string that looks like a key is a string that
looks like a key, wherever it sits. It was rewritten, not allowlisted.

Known cost, stated rather than hidden: the scanner strips quotes before this
check, so a quoted `"false"` — a string to YAML — is also exempt. That is the
same limitation the file already documents for having no parser.

---

## 9. Renovate

`renovate.json5` was added. Its purpose is to **keep the existing pins current,
not to relax them**. A hand-pinned digest is a pin nobody refreshes.

- `helpers:pinGitHubActionDigests` and `pinDigests: true` on the Actions,
  gitlabci and docker managers: refresh the SHA or digest in place.
- `automerge: false` and `platformAutomerge: false` are set explicitly, so a
  future preset cannot enable them silently. No `autoApprove`, no
  `autodiscover`.
- Weekly schedule, concurrency limits. `vulnerabilityAlerts` bypasses the
  schedule but still gets a human.
- The `mise` manager is disabled, with the reason recorded in the file. See F4.

---

## 10. What this audit did not do

- **No history rewrite.** No `filter-repo`, `filter-branch`, interactive rebase,
  amend of a published commit or force push.
- **No committed value deleted, redacted or altered.** Findings F1 to F4 are
  reported in place.
- **`.gitleaks.toml` unchanged.** No allowlist added, no rule removed.
- **Both lefthook hooks unchanged.** No CI job removed, disabled or relaxed.
- **The manual `audit:secrets-live` job keeps `allow_failure: true`.** That is a
  documented decision in `.gitlab-ci.yml:70-79`, not a weakened gate.
- **No LICENSE, SECURITY.md, CONTRIBUTING.md or CODE_OF_CONDUCT.md added.**
- **The `--live` and network-dependent audits were not run here.**
  `mise run audit:secrets-live` needs outbound calls to credential providers.
  The GitHub `secrets-live` job is the authority for that question, and its
  result is whatever the pipeline reports — not something this document
  predicts.

---

## 11. Verdict

The repository is **safe to publish** with respect to secrets. Four independent
scans over full history, merge diffs and tracked content are clean, and the
scanned revision set provably covers `master`.

Four findings are open and reported: a workstation host name in tracked text
(F1), machine names in keymap file names (F2), three missing rows in the README
attribution table (F3), and an unpinned tool chain (F4). None is a credential.
F3 is the one with an external obligation attached, because it concerns a
copyleft attribution notice.

A fifth finding (F5), a pre-existing `lint:lua` failure that had kept the GitHub
workflow red on `master` for its last two runs, was fixed here rather than left
open, and is documented as an out-of-scope change.
