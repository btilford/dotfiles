#!/usr/bin/env sh
# Print every YAML file in the repo, one path per line.
#
# The single source of truth for "what does yamllint run against", called by ALL
# THREE surfaces: `mise run lint:yaml`, the GitLab lint:yaml job, and the GitHub
# lint workflow. Those are required to stay aligned (see CLAUDE.md, "Linting &
# CI"); sharing the selector makes that structural instead of a thing to
# remember.
#
# POSIX sh with only find, for the same reason as shell-files.sh: the CI image
# (pipelinecomponents/yamllint) ships no git, so `git ls-files` is unavailable
# and selection has to be path-based rather than by tracked-ness.
#
# Unlike shell scripts there is no shebang to inspect, so extension is all we
# have — which is fine, since YAML is always named .yml or .yaml here.

set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

# The two exclusions below are gitignored, machine-provisioned configs. They do
# not exist in a fresh clone, so CI never sees them — but they DO exist on a
# provisioned machine, where find would happily pick them up and lint local
# state that can never be committed. Excluding them keeps the local run and the
# CI run selecting the same set. Their committed .example siblings are linted.
find . -type f \( -name '*.yml' -o -name '*.yaml' \) \
  -not -path './.git/*' \
  -not -path './build/*' \
  -not -path './docker/.docker/mcp/config.yaml' \
  -not -path './gh/.config/gh/hosts.yml' \
  -print |
  sort
