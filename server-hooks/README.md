# server-hooks

Git **server-side** hooks for the self-hosted GitLab instance. Not a stow
package — nothing here is installed into `$HOME`, and nothing here runs on this
machine. It lives in the repo so the gate is reviewable and version-controlled
rather than being a file someone once pasted onto a server.

## Why a server hook at all

Every other secret gate in this repo is client-side and therefore optional:

| Gate | Bypassed by |
| --- | --- |
| `git/.config/git/hooks/pre-commit` (via `init.templateDir`) | `git commit --no-verify` |
| `hk.pkl` pre-commit | `git commit --no-verify`, or `HK=0` |
| `.gitlab-ci.yml` / GitHub Actions | nothing — but it runs **after** the push |

CI is the honest backstop, and it is still too late: by the time a pipeline
reports, the objects are on the server and the GitHub mirror has already had a
chance to sync them. A `pre-receive` hook rejects the push itself, so nothing is
ever written.

Git server hooks are available on **Free** for GitLab Self-Managed. This is not
the Ultimate-tier "Secret Push Protection" feature; it is the free equivalent,
built from the same `betterleaks` config the rest of the repo uses.

## Install (per GitLab instance, once)

Hooks in the **global** server-hook directory apply to every repository on the
instance. It defaults to `gitlab-shell/hooks` under the `git` user's home; read
the instance's configured value rather than assuming, and export it first:

```sh
# on the GitLab server
HOOKS_DIR="$(gitlab-rails runner 'puts Gitlab.config.gitlab_shell.hooks_path' 2>/dev/null)"
: "${HOOKS_DIR:?read the configured hooks path before installing}"

install -d "$HOOKS_DIR/pre-receive.d"
install -m 0755 pre-receive.d/betterleaks "$HOOKS_DIR/pre-receive.d/betterleaks"
rm -f "$HOOKS_DIR/pre-receive.d/gitleaks"   # the file this replaced, 2026-08-24
betterleaks version   # must be on PATH for the git user
```

(The literal default path is not written out here: `no-local-values.sh` reads an
absolute `/home/<user>/…` as machine-local content and rejects the commit, which
is the gate working as designed even though this one is a server path.)

Verify with a throwaway branch containing a fake credential — it should be
rejected, and the report should name the file and line **without printing the
value**.

## Design notes

- **Fails closed when betterleaks is missing.** A security gate that disables itself
  when its binary disappears is worse than no gate, because the green push then
  reads as proof. The deliberate override is
  `BETTERLEAKS_PRE_RECEIVE_DISABLE=1` in the server environment (the older
  `GITLEAKS_PRE_RECEIVE_DISABLE` is still read, so an instance that had it set
  did not start enforcing at the rename) — an admin action,
  not something a pusher can set.
- **Scans the pushed range only** (`--log-opts`), and for a new ref uses
  `--not --all` so it does not re-scan history the server already has. This hook
  sits in the push path; a full-history scan on every push would not be viable.
- **`--redact`.** Output reaches the pusher's terminal and the server log. File
  and line are enough to act on; reprinting the value copies the secret into two
  more places.
- **No repo config.** It runs with betterleaks' default rule set, because the
  hook is instance-wide and cannot assume any particular repo's
  `.betterleaks.toml`.
  Repo-specific rules (like this repo's `json-credential-value`) still run in the
  client-side hooks and in CI. If the instance is only used for repos that carry
  a config, add `-c` pointing at a copy on the server.
