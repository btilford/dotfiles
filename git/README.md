# git — the complete git configuration

Stow package. `stow --no-folding git` from `~/dotfiles`.

> This README is the tour. The full rationale — why each seam exists and what
> broke when it did not — is in [`CLAUDE.md`](CLAUDE.md).

| Path | Installs to |
|------|-------------|
| `.gitconfig` | `~/.gitconfig` — entry point, `[include]`s everything below |
| `.config/git/*.gitconfig` | config fragments |
| `.config/git/profiles/` | identity profiles |
| `.config/git/hooks/` | the real `post-checkout` / `pre-commit` logic |
| `.config/git/templates/` | source for `init.templateDir` (**not** pointed at directly) |
| `.local/bin/gh-git-credential`, `glab-git-credential` | credential helper wrappers |
| `.local/bin/git-template-sync`, `git-spice-hook-install` | setup helpers |

| Fragment | Holds |
|----------|-------|
| `core.gitconfig` | editor, delta pager, excludesfile, per-host credential helpers, `init.templateDir` |
| `aliases.gitconfig` | aliases |
| `commands.gitconfig` | push/pull/fetch/merge/diff behaviour, difftools |
| `shell.gitconfig` | colour, rebase editor, **notes refspecs** |
| `spice.gitconfig` | git-spice settings (forge URLs are machine-local) |
| `flow.gitconfig` | git-flow branch prefixes |
| `dirs.gitconfig` | `includeIf "gitdir:…"` identity routing |
| `web.gitconfig` | browser, instaweb |

## Identity profiles

`dirs.gitconfig` picks an identity from the working directory — no manual
switching.

| Directory | Profile | Identity |
|-----------|---------|----------|
| `~/work/anon/` and client dirs (local-only entries) | `anon.gitconfig` | name `nil`, no GPG |
| explicitly listed directories | `default.gitconfig` | btilford, GPG signed |

**There is no catch-all `includeIf`.** A directory not listed gets no identity and
commits fail outright.

`profiles/default.gitconfig` is **not in this repo** — it is stowed from
`private-dotfiles`. `default.example.gitconfig` here shows the shape. The work
profile and its `includeIf` are out of tree too: they name an employer, a work
account and a ticket tracker.

## Credential helpers

```ini
[credential "https://github.com"]
    helper = !~/.local/bin/gh-git-credential
```

**The `!` prefix is load-bearing.** Without it git treats the value as a binary
name, does not expand `~`, and authentication for that host breaks *silently*.
The self-hosted GitLab gets the same treatment, but its hostname is private
infrastructure, so that block lives in `~/.gitconfig.local`.

Git Credential Manager is the fallback for everything else and is **never** added
to this package — its path varies per machine and package manager.

## Hooks: `templateDir`, not `core.hooksPath`

New clones get a `post-checkout` (git-spice auto-tracking) and a `pre-commit`
(gitleaks) hook. Two rules behind that:

- **`init.templateDir` must never point at `~/.config/git/templates`.** Git copies
  template entries *as symlinks, preserving the relative target*, and stow makes
  every file a relative symlink — so every new repo would get a **dangling**
  hook that silently never runs. `git-template-sync` does a `cp -RL` into
  `~/.local/share/git-template` and fails loudly if any symlink survives.
- **`core.hooksPath` was rejected.** It replaces the hooks directory wholesale, so
  any hook name absent from it stops existing in *every* repo — verified, and a
  secret-carrying commit went through because of it.

The two template hooks are deliberately trivial and byte-identical: resolve `$0`'s
basename, exec `~/.config/git/hooks/<name>`. Real logic stays in the stowed tree
and reaches every repo immediately. Keep them that way.

## `remote.origin.push` — both lines or neither

```ini
[remote "origin"]
    fetch = +refs/notes/*:refs/notes/*
    push = HEAD
    push = +refs/notes/*:refs/notes/*
```

Setting `remote.<name>.push` at all **replaces** git's default push refspec. With
only the notes line, `git push` pushed notes and nothing else — reporting
`Everything up-to-date` on a branch a commit ahead. No error, no warning, and
`push.default = current` is ignored outright because an explicit refspec always
wins. This is global config, so it applied to every repo on the machine.

**Never single-quote a git config value.** git config is not shell: double quotes
are syntax git strips, single quotes end up *inside* the value. Both lines above
were once single-quoted, so the refspec was literally
`'+refs/notes/*:refs/notes/*'` and matched no ref ever.

```console
git config --get-all remote.origin.push   # no quote characters in the output
git push --dry-run                        # must name the current branch
```

## Setup on a new machine

```sh
stow --no-folding git
gh auth login
glab auth login --hostname <your-gitlab-host>
mise run setup:git-template     # generate ~/.local/share/git-template
mise run setup:git-spice        # forge URL check, auth check, hook retrofit
```

Order matters for git-spice: set `spice.forge.gitlab.url` in `~/.gitconfig.local`
**before** `git-spice auth login`, or the token is keyed to gitlab.com and a
self-hosted remote reports `gitlab: not logged in`. The config form is
`[spice "forge.gitlab"]` + `url = …` — dots are illegal in a variable name, and
`[spice "forge"]` with `gitlab.url = …` makes **every** git command fail with
`bad config line`.

## `~/.gitconfig.local` is the only local seam

git has no directory include — `include.path` takes one path per line and there is
no `.d/` mechanism. `.gitconfig` includes `~/.gitconfig.local` last, so it wins.
It holds: the GCM block, the self-hosted GitLab credential block, the git-spice
forge URL, and the work identity profile with its `includeIf`.
