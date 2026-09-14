#!/usr/bin/env bash
# Pre-publish checks — the repo-local mirror of the org publishing checklist.
# Scans tracked text files; exits 1 on any hit. Run by CI on every push and
# locally via .githooks/pre-push.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

node scripts/workbook-contract-check.mjs

fail=0

scan() {
  local label="$1" pattern="$2"
  # Text files only; base64 image payloads live inside HTML, so cap line
  # relevance by matching the pattern itself, not whole lines.
  if git grep -I -n -E "$pattern" -- . ':!scripts/publish-checks.sh' >/tmp/publish-check-hits 2>/dev/null; then
    echo "FAIL [$label]"
    head -10 /tmp/publish-check-hits
    fail=1
  else
    echo "ok   [$label]"
  fi
}

# Secrets
scan "aws access key"        'AKIA[0-9A-Z]{16}'
scan "private key block"     'BEGIN [A-Z ]*PRIVATE KEY'
scan "github token"          'gh[pousr]_[A-Za-z0-9]{20,}'
scan "slack token"           'xox[abpr]-[A-Za-z0-9-]{10,}'
scan "live workato mcp token" 'wkt_token=[A-Za-z0-9_-]{10,}'

# Inclusive language (trainer ruling 2026-07-09).
#
# EXEMPTION (trainer, 2026-09-14): the shared semantic layout catalog
# workato-training-semantic-layouts@1 names one of its classes
# "hands-on-activity", and the renderer stamps that token onto every task
# element as a class and a data attribute. It is generated markup, not
# language anyone reads, so it is exempt. Prose is not exempt: "hands on"
# with a space, or any other form a learner could read, still fails. The
# exemption is deliberately the exact generated token and nothing wider.
if git grep -I -n -E '[Hh]ands[- ]on' -- . ':!scripts/publish-checks.sh' \
   | grep -v -E 'semantic-layout--hands-on-activity|data-semantic-class="hands-on-activity"' \
   >/tmp/publish-check-hits 2>/dev/null; then
  echo "FAIL [non-inclusive: hands-on]"
  head -10 /tmp/publish-check-hits
  fail=1
else
  echo "ok   [non-inclusive: hands-on]  (catalog class token exempt)"
fi

# Internal surfaces
scan "internal repo pointer" 'static-web|Workato-TFO/bakery|PUBLISHING\.md'
scan "okta url"              '[a-z0-9.-]+\.okta\.com'
scan "internal confluence"   'workato\.atlassian\.net'
scan "slack archive link"    'slack\.com/archives'
scan "employee email"        '[A-Za-z0-9._%+-]+@workato\.com'

# Collaborator names — never in tracked content, commit messages, or PR text.
# (PRs and their commit lists become public with the repo and cannot be
# suppressed or rewritten — keep names out from the start.)
NAME_PATTERN='[Mm]ichael|[Mm]atias|[Ff]ederico|\bmpak\b|[Pp]aktinat|[Hh]eiwad|\b[Oo]sman\b'
if git grep -I -n -E "$NAME_PATTERN" -- . ':!scripts/publish-checks.sh' >/tmp/publish-check-hits 2>/dev/null; then
  echo "FAIL [collaborator name in content]"; head -10 /tmp/publish-check-hits; fail=1
else
  echo "ok   [collaborator name in content]"
fi
if git log --format='%s%n%b' | grep -n -E "$NAME_PATTERN" >/tmp/publish-check-hits 2>/dev/null; then
  echo "FAIL [collaborator name in commit history]"; head -10 /tmp/publish-check-hits; fail=1
else
  echo "ok   [collaborator name in commit history]"
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Publish checks failed — nothing internal may land in this repo."
  exit 1
fi
echo "All publish checks passed."
