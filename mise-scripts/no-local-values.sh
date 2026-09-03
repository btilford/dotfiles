#!/usr/bin/env sh
# Fail if tracked content contains a machine-local VALUE, or a generic private
# pattern. Guards the public mirror against re-introducing what was scrubbed.
#
#   mise-scripts/no-local-values.sh              # staged changes (pre-commit)
#   mise-scripts/no-local-values.sh --all        # whole tree (mise run lint:private, CI)
#   mise-scripts/no-local-values.sh --message F  # a commit message (commit-msg hook)
#
# A commit message is published exactly like file content and was previously
# ungated — nothing stopped an internal hostname or a client name being explained
# in a commit body. `--message` runs the same three halves over the message file.
#
# Two halves, on purpose:
#
# 1. VALUES from ~/.config/dotfiles/local.env. A denylist of the actual hostnames
#    cannot live in this repo — committing it would publish the very strings it
#    protects. So the values are read from the untracked file at run time, and
#    only the VARIABLE NAME is ever printed. Side effect worth having: this also
#    blocks committing local.env itself.
#    Skipped when local.env is absent, e.g. in CI. That is why half 2 exists.
#
# 2. GENERIC patterns that are private by shape rather than by value, so they are
#    safe to write down and work everywhere including CI.
#
# 3. LOCAL patterns from ~/.config/dotfiles/scrub.patterns — an untracked list of
#    regexes for things private by *identity* rather than by shape or by being
#    config: an employer name, a client, an internal project directory. No pattern
#    can distinguish a company name from any other word, and such a name is not a
#    value any config consumes, so halves 1 and 2 are both blind to it. Same
#    discipline as half 1: the file is untracked and only its LINE NUMBER is ever
#    printed, never the pattern.
#
# POSIX sh with only git/grep/sed: the GitLab CI image ships no extra tooling, the
# same constraint mise-scripts/shell-files.sh works under.

set -u

env_file="${DOTFILES_LOCAL_ENV:-$HOME/.config/dotfiles/local.env}"
patterns_file="${DOTFILES_SCRUB_PATTERNS:-$HOME/.config/dotfiles/scrub.patterns}"
mode="${1:-staged}"
status=0

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

# Content under test. Staged mode looks at the diff so unrelated pre-existing
# debt in other files never blocks a commit.
if [ "$mode" = "--all" ]; then
  content=$(git ls-files -z | xargs -0 grep -nIH '' 2> /dev/null)
elif [ "$mode" = "--message" ]; then
  msg_file="${2:-}"
  [ -n "$msg_file" ] || {
    echo "  ✗ --message needs a file" >&2
    exit 2
  }
  [ -r "$msg_file" ] || {
    echo "  ✗ cannot read $msg_file" >&2
    exit 2
  }
  # Comment lines are git's own template and never end up in the message.
  content=$(grep -vE '^#' "$msg_file")
else
  content=$(git diff --cached --unified=0 --no-color | grep -E '^\+' | grep -v '^+++')
fi

[ -n "$content" ] || exit 0

# ---------------------------------------------------------------------------
# 1. Values from local.env
# ---------------------------------------------------------------------------
# Matching is grep -F, on purpose: a value may contain regex metacharacters, and
# treating it as a pattern would either error or match the wrong thing. The
# assumption that comes with byte-exact matching is that a value appears in a
# file exactly as it appears in local.env. That holds for prose, code and
# config. It does NOT hold for markdown.
#
# A markdown table delimits cells with "|", so a literal pipe inside a cell must
# be written "\|" or the table splits there. The value goes in as one string and
# lands as a different one, and grep -F compares bytes:
#
#   verbatim value flagged?  YES
#   CLAUDE.md:37 flagged?    NO      <- same value, in a table cell
#
# That is not hypothetical. It is how a private value sat in tracked content
# while this gate reported clean, and the escape was not a mistake — writing the
# value in a table CORRECTLY is what defeated the check. The gate was weakest
# exactly where the documentation was most careful.
#
# The drift runs in BOTH directions, which the first version of this fix got
# wrong. A value is often itself a regex, so it arrives carrying its own escapes
# — and prose about it tends to drop those while markdown adds its own. The real
# case had the value's backslash-dot removed AND pipes escaped, so de-escaping
# only the content still missed it.
#
# So both sides are normalised: backslashes before punctuation are stripped from
# the content and from the value, and the comparison is made on the results, in
# addition to the verbatim one. Stripping is safe in this direction — it can only
# make a string more literal, never invent a match — which is why it is done to
# both strings rather than by turning the value into a pattern. The latter would
# mean giving up grep -F's one real safety property.
#
# Still NOT covered, and worth knowing: a value broken across two lines (by a
# formatter or a hand wrap) matches nothing, because content is scanned per
# line. Entity-encoded and percent-encoded forms are likewise untouched.
unescape() { sed 's/\\\([]|`*_[<>#+.!(){}~-]\)/\1/g'; }
content_unescaped=$(printf '%s' "$content" | unescape)

if [ -r "$env_file" ]; then
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac

    var=$(printf '%s' "$line" | sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/p')
    val=$(printf '%s' "$line" | sed -nE 's/^[^=]*=[[:space:]]*(.*)$/\1/p')

    [ -n "$var" ] || continue

    # Variables whose values are not private by nature, and which therefore MUST
    # be allowed to appear in tracked files. This list is about false positives,
    # not exemptions: nothing here identifies a machine, a network or a person.
    #
    #   DOTFILES_PROFILE  is literally "personal" or "work". "personal" is eight
    #                     characters, so it clears the length floor below, and it
    #                     is an ordinary English word that appears in prose and
    #                     comments constantly — it would fail every commit.
    #   HF_HOME           a filesystem path to a model store. Discloses nothing,
    #   HF_HUB_CACHE      and the example file needs to show the real shape.
    #
    # Keep this list SHORT and justify each addition. A variable belongs here
    # only if publishing its value is harmless; if in doubt, leave it out and
    # change the value instead.
    case "$var" in
      DOTFILES_PROFILE | HF_HOME | HF_HUB_CACHE) continue ;;
    esac

    # LOOPBACK VALUES ARE EXEMPT BY VALUE, NOT BY VARIABLE NAME.
    #
    # A loopback address resolves to whatever host reads it, so it names no
    # machine and discloses no network — it is the one class of endpoint that is
    # safe to publish by construction. Once a machine runs its own inference
    # server, its AI_GATEWAY and OLLAMA_HOST are loopback, and a name-based
    # exemption would then wave through whatever those variables held next.
    # Testing the value keeps the gate armed if either is ever repointed at a
    # real host.
    #
    # This is what lets 127.0.0.1 appear in continue/.continue/config.yaml, the
    # ollama LaunchAgent and the atuin-ai-server compose file — all of which need
    # a literal, because those formats have no environment interpolation.
    case "$val" in
      127.0.0.1 | 127.0.0.1:* | \
        http://127.0.0.1 | http://127.0.0.1[:/]* | \
        localhost | localhost:* | http://localhost | http://localhost[:/]* | \
        "[::1]" | "[::1]:"* | "http://[::1]" | "http://[::1][:/]"*) continue ;;
    esac

    # Short values produce false positives (a bare port, "true", an empty var).
    [ ${#val} -ge 8 ] || continue

    val_unescaped=$(printf '%s' "$val" | unescape)
    if printf '%s' "$content" | grep -qF -- "$val" ||
      printf '%s' "$content_unescaped" | grep -qF -- "$val" ||
      printf '%s' "$content_unescaped" | grep -qF -- "$val_unescaped"; then
      echo "  ✗ content contains the value of \$$var" >&2
      status=1
    fi
  done < "$env_file"
else
  echo "  · $env_file not readable — value check skipped (pattern check still runs)" >&2
fi

# ---------------------------------------------------------------------------
# 2. Generic patterns
# ---------------------------------------------------------------------------
# check_pattern LABEL PATTERN [EXTRA_EXCLUDE]
#
# EXTRA_EXCLUDE is per-pattern, so a narrow exemption cannot silently weaken the
# other checks — the shared list below applies to everything and stays small.
check_pattern() {
  label="$1"
  pattern="$2"
  extra="${3:-}"
  hits=$(printf '%s' "$content" | grep -nE "$pattern" | grep -vE 'example|placeholder|<[a-z-]+>|0\.0\.0\.0|127\.0\.0\.1|/(Users|home)/(me|user|username|you|youruser)/|SERIAL|MODEL|VENDOR|Vendor Inc|555[-. ]?01[0-9]{2}')
  [ -n "$extra" ] && hits=$(printf '%s' "$hits" | grep -vE "$extra")
  hits=$(printf '%s' "$hits" | head -5)
  if [ -n "$hits" ]; then
    echo "  ✗ $label:" >&2
    if [ "$mode" = "--all" ]; then
      # Tree mode is the one CI runs, and CI job logs are a published surface once
      # the mirror is public. Printing the offending line there would disclose the
      # exact value this gate exists to keep out — the failure would leak what the
      # commit was blocked for. Location only. Fields are
      # <stream-index>:<path>:<line>:<text> — the index comes from the grep -n in
      # check_pattern, the path and line from the grep -nIH that built `content`.
      printf '%s\n' "$hits" | cut -d: -f2,3 | sed 's/^/      /' >&2
      echo "      (content withheld — run: mise-scripts/no-local-values.sh --all locally)" >&2
    else
      # Staged mode runs in the author's own terminal, on lines they just wrote.
      printf '%s\n' "$hits" | sed 's/^/      /' >&2
    fi
    status=1
  fi
}

# ---------------------------------------------------------------------------
# IP addresses: ALL of them, v4 and v6, minus an explicit allowlist.
# ---------------------------------------------------------------------------
# This used to match RFC1918 addresses only, and required all four octets so
# that prose about "10.0.0.0/8" would not trip it. Both halves of that were
# wrong:
#
#   - A two-octet PREFIX is not an address, so it never matched. A real one sat
#     in tracked content and in 47 historical blobs without ever being flagged.
#     A /16 prefix is arguably better recon than a single host anyway.
#   - Private-by-RFC is not the same as private-by-consequence. A public address
#     belonging to this network discloses more, not less, than an RFC1918 one.
#
# So the rule is now: an IP-shaped literal is a finding unless it is on the
# allowlist below. Adding to the allowlist is a deliberate, reviewable act;
# forgetting to extend a denylist is silent, which is how the last one got out.
#
# IP_ALLOW holds whole addresses, one extended-regex alternative each, anchored
# at both ends when matched. Only put something here if publishing it is
# harmless on ANY network:
#
#   0.0.0.0 255.255.255.255   wildcard / broadcast, not a host
#   127.0.0.1 ::1             loopback, identical on every machine
#   10.0.0.0 172.16.0.0
#   192.168.0.0               the RFC1918 range BASES, as written in the RFCs.
#                             A base names a range; it identifies no network.
#   192.0.2.x 198.51.100.x
#   203.0.113.x 2001:db8::    RFC5737 / RFC3849 documentation ranges. These
#                             exist precisely to be published — prefer them in
#                             any example over a made-up address.
#
# The bare "10.0." / "172.16." / "192.168." entries exist for the PREFIX check
# only, so that prose naming a range base ("a bare 10.0.0.0/8") is not a finding.
# They do not weaken the address check: 10.0.5.7 is still a full quad, is not on  # ip-gate-allow
# this list, and is still blocked.
#
# NOT allowlisted, deliberately: link-local (169.254/fe80::) and CGNAT
# (100.64/10). They are as machine-identifying as anything else here.
IP_ALLOW='0\.0\.0\.0|255\.255\.255\.255|127\.0\.0\.1|10\.0\.0\.0|172\.16\.0\.0|192\.168\.0\.0|192\.0\.2\.[0-9]{1,3}|198\.51\.100\.[0-9]{1,3}|203\.0\.113\.[0-9]{1,3}|10\.0\.|172\.16\.|192\.168\.|::1|2001:[Dd][Bb]8:[0-9A-Fa-f:]*' # ip-gate-allow

# IPv4: any dotted quad. Bounded so a version string's tail is not read as one.
IPV4_RE='(^|[^0-9.])[0-9]{1,3}(\.[0-9]{1,3}){3}([^0-9.]|$)' # ip-gate-allow

# IPv6: require either a "::" run or the full eight groups. That distinction is
# what keeps timestamps out — "17:16:57" and "00:00:01.000" have neither, and a
# naive ":"-separated-hex rule flags every one of them.
#
# Requiring a hex group ADJACENT to the "::" is what keeps the rest of the tree
# out: a bare "::" appears 35 times here, and zsh completion specs (::name),
# Perl (JSON::XS), Haskell and Qt (QIODevice::write) all use "::" with
# non-hex neighbours. Verified against the whole tree, not assumed.
# IPv6 is detected in two stages: a loose token match here, then a hex-group
# count in check_ip. A pure regex cannot do it, and the failures are not
# theoretical — every one below came from this tree.
#
# The token must contain "::" or the full seven colons, and must be bounded by
# something that is NOT alphanumeric. The alphanumeric part is what matters:
# hex-only boundaries are not enough, because a scope operator lands mid-word.
#
#   IPC::Open2      -> "C::"   C is hex; preceded by P, rejected on boundary
#   Cwd::cwd()      -> "d::c"  BOTH sides hex, two groups, would otherwise pass  # ip-gate-allow
#   Win32::GetCwd   -> "32::"  3 and 2 are hex; preceded by n, rejected
#   ::name ::filter -> "::"    followed by an alnum, rejected
#   "::" bare (x35) ->         zero hex groups, dropped by the count
#
# Timestamps never reach here: "17:16:57" has no "::" and only two colons.
IPV6_TOKEN='[0-9A-Fa-f:]*::[0-9A-Fa-f:]*|([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}' # ip-gate-allow
IPV6_RE="(^|[^0-9A-Za-z_:])($IPV6_TOKEN)([^0-9A-Za-z_:]|$)"                      # ip-gate-allow

# A PREFIX is not an address, and this is the case the old RFC1918 rule missed
# outright: it required four octets, so a bare two-octet prefix never matched —
# and one sat in tracked content and in 47 historical blobs because of it. A /16
# names a network, which is at least as useful to an attacker as a single host.
#
# Restricted to the private ranges on purpose. A general "two dotted octets"
# rule would flag every version number in the tree.
IPV4_PREFIX_RE='(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]))\.' # ip-gate-allow

IP_VERSIONISH='[A-Za-z][A-Za-z0-9]*-[0-9]{1,3}(\.[0-9]{1,3}){3}' # ip-gate-allow

# check_ip LABEL CANDIDATE_RE EXTRACT_RE
#
# Unlike check_pattern, this does NOT drop a whole line because it contains one
# allowlisted value. It extracts every address on the line and reports the line
# if ANY of them is not allowlisted — otherwise "127.0.0.1 and <real address>"
# on one line would pass, which is a plausible way to write a config comment.
check_ip() {
  label="$1"
  candidate_re="$2"
  extract_re="$3"
  hits=""

  # Field layout is <path>:<line>:<text> (or <index>:... in staged mode); the
  # address itself is extracted from the whole record, so a path that looks like
  # an address would also be caught, which is the intent — see the kmonad
  # filename case in the repo CLAUDE.md.
  printf '%s\n' "$content" | grep -nE "$candidate_re" | while IFS= read -r record; do
    # Strip the <path>:<line>: location prefix that --all mode prepends before
    # extracting. Without this, that prefix IS the finding: a path ending
    # ".sample:15:" contains "15::", a valid compressed run, so every vendored
    # hook sample in the tree reported itself.
    # [^: ] for the path component, not [^:]. With [^:]* the strip is greedy
    # across spaces, so the record "1:host fd00:1234::beef" had "1:host fd00:1234:"  # ip-gate-allow
    # removed and the check saw ":beef" — the address was eaten by its own
    # location-stripper and every compressed IPv6 silently passed.
    text=$(printf '%s' "$record" | sed -E 's/^[0-9]+:[^: ]*:[0-9]+://')
    # Per-LINE opt-out, not a path exemption. This file necessarily contains
    # IP-shaped literals — the allowlist and the patterns themselves — and
    # would otherwise fail its own check. Exempting the whole file instead
    # would blind it to a real address parked here, which is the same mistake
    # as a `paths` allowlist in .betterleaks.toml (see the repo CLAUDE.md).
    # A marker is one visible token on one line, and shows up in review.
    case "$text" in *ip-gate-allow*) continue ;; esac

    bad=0
    for addr in $(printf '%s' "$text" | grep -oE "$extract_re"); do
      printf '%s' "$addr" | grep -qE "^($IP_ALLOW)$" && continue
      printf '%s' "$text" | grep -qE "$IP_VERSIONISH" && continue
      # An IPv6 token needs two hex groups to be an address. One group is a
      # scope operator's neighbour, zero is a bare "::".
      case "$addr" in
        *::* | *:*:*:*:*:*:*:*)
          groups=$(printf '%s' "$addr" | tr ':' '\n' | grep -c '[0-9A-Fa-f]')
          [ "$groups" -lt 2 ] && continue
          ;;
      esac
      bad=1
    done
    [ "$bad" -eq 1 ] && printf '%s\n' "$record"
  done > "$ip_tmp"

  hits=$(head -5 "$ip_tmp")
  : > "$ip_tmp"

  if [ -n "$hits" ]; then
    echo "  ✗ $label:" >&2
    if [ "$mode" = "--all" ]; then
      printf '%s\n' "$hits" | cut -d: -f2,3 | sed 's/^/      /' >&2
      echo "      (content withheld — run: mise-scripts/no-local-values.sh --all locally)" >&2
    else
      printf '%s\n' "$hits" | sed 's/^/      /' >&2
    fi
    status=1
  fi
}

ip_tmp=$(mktemp) || exit 1
trap 'rm -f "$ip_tmp"' EXIT INT TERM

check_ip "IPv4 address" "$IPV4_RE" '[0-9]{1,3}(\.[0-9]{1,3}){3}'
# Extract EXACTLY two octets and the trailing dot, never three. A greedy
# extractor turns "10.0.0.0/8" into "10.0.0." which matches no allowlist entry,
# so prose naming a range base failed the gate.
check_ip "IPv4 network prefix" "$IPV4_PREFIX_RE" '[0-9]{1,3}\.[0-9]{1,3}\.'
check_ip "IPv6 address" "$IPV6_RE" "$IPV6_TOKEN"

check_pattern "absolute home path" '/home/[a-z][a-z0-9_-]+/|/Users/[a-z][a-z0-9_-]+/'
check_pattern "hardware serial in a monitor descriptor" 'desc:[^"]*[A-Z0-9]{6,}'

# US/NANP phone numbers, in every common written form: 212-555-0143, (212) 555-0143,
# 212.555.0143, 212 555 0143, 2125550143, and each of those with a +1 / 1- prefix.
#
# Three things keep the false-positive rate at zero on this tree:
#
#   - NANP structure, not "ten digits": area and exchange must start [2-9]. That
#     alone rejects unix timestamps (17xxxxxxxx) and most sequential digit runs.
#   - Explicit boundaries rather than \b — the CI image's busybox grep cannot be
#     relied on for it. Without them the bare 10-digit form matched INSIDE longer
#     numbers: GLSL float matrices and git SHAs in lazy-lock.json, 31 hits.
#   - 555-01xx is excluded above. NANP reserves it for fiction, so documentation
#     can use an example number without failing the gate.
check_pattern "US phone number" '(^|[^0-9A-Za-z.])(\+?1[-. ]?)?(\([2-9][0-9]{2}\)|[2-9][0-9]{2})[-. ]?[2-9][0-9]{2}[-. ]?[0-9]{4}([^0-9A-Za-z]|$)'

# Email addresses. Exempt by shape, not by path:
#
#   - `users.noreply.*` and `no-reply@` — these EXIST to be published. GitHub's
#     ID+user@users.noreply.github.com and GitLab's private commit email are the
#     correct thing to commit, so flagging them would fight the fix.
#   - attribution lines — SPDX-FileCopyrightText, `Author:`, `Maintainer:`,
#     `Copyright`. Three vendored files carry their upstream authors' addresses
#     that way, and stripping them would remove attribution from someone else's
#     work (the SPDX one is a licence header). Exempting the ATTRIBUTION FORM
#     rather than those file paths means a new vendored file is covered too, while
#     a bare address anywhere still fails.
check_pattern "email address" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  'users\.noreply\.|no-?reply@|@a\.hole|SPDX-FileCopyrightText|[Mm]aintainer[[:space:]]*:|[Aa]uthor[[:space:]]*:|Copyright'

# ---------------------------------------------------------------------------
# 3. Local patterns
# ---------------------------------------------------------------------------
if [ -r "$patterns_file" ]; then
  pat_line=0
  while IFS= read -r pattern; do
    pat_line=$((pat_line + 1))
    case "$pattern" in '' | '#'*) continue ;; esac

    # A pattern that does not compile makes grep exit 2, which is neither "found"
    # nor "clean". Left unchecked it would read as a pass and silently disable
    # that line for good, so it is reported as a failure instead.
    printf '' | grep -Eiq -- "$pattern" 2> /dev/null
    if [ $? -gt 1 ]; then
      echo "  ✗ $patterns_file:$pat_line is not a valid regex — gate cannot run it" >&2
      status=1
      continue
    fi

    hits=$(printf '%s' "$content" | grep -nEi -- "$pattern" | head -5)
    [ -n "$hits" ] || continue

    # The pattern itself is private — it spells out the thing being kept out of
    # the mirror — so only its line number is named, never its text.
    echo "  ✗ matches $patterns_file:$pat_line" >&2
    if [ "$mode" = "--all" ]; then
      printf '%s\n' "$hits" | cut -d: -f2,3 | sed 's/^/      /' >&2
      echo "      (content withheld — run: mise-scripts/no-local-values.sh --all locally)" >&2
    else
      printf '%s\n' "$hits" | sed 's/^/      /' >&2
    fi
    status=1
  done < "$patterns_file"
fi

if [ "$status" -ne 0 ]; then
  cat >&2 << 'MSG'

  Machine-local content must not be committed. Options:
    - move the value into ~/.config/dotfiles/local.env and read it from the
      environment (see commands/.local/share/dotfiles/required-env)
    - use $HOME instead of an absolute path
    - for a monitor table, use ~/.config/hypr/lua/monitors.local.lua
    - for a name that is private by identity (employer, client, internal
      project), add a regex to ~/.config/dotfiles/scrub.patterns

  This gate also runs in CI, where --no-verify cannot skip it.
MSG
fi

exit "$status"
