#!/bin/bash
#
# AOC SessionStart hook — profiles-only glue. All real work lives in the `aoc`
# CLI (package cli_aoc); edit `aoc profiles` there, not this hook.
#
# This hook ONLY installs/upgrades the AI asset profiles declared in
# .agents/aoc.yaml. It never runs context sync and never creates or updates
# context files (.agents/context.md, code-architecture.md, etc.).

# fd 3 is the original stdout, used for hook signals (JSON to the agent).
# Only set it up if it's not already open (the caller may have redirected it).
if { true >&3; } 2>/dev/null; then
  :
else
  exec 3>&1
fi
exec 1>&2

resolve_runner() {
  if fury aoc --version >/dev/null 2>&1; then
    AOC_CMD=(fury aoc)
    return 0
  fi
  if aoc --version >/dev/null 2>&1; then
    AOC_CMD=(aoc)
    return 0
  fi
  return 1
}

NEEDS_INSTALL=false
if ! resolve_runner; then
  NEEDS_INSTALL=true
fi

if [[ "$NEEDS_INSTALL" == "true" ]]; then
  echo "INFO [aoc] installing cli_aoc..."
  if ! fury registry login >/dev/null 2>&1; then
    echo "ERROR [aoc] fury registry login failed"
    exec 3>&-
    exit 1
  fi
fi

if [[ "$NEEDS_INSTALL" == "true" || "${AOC_CMD[0]:-}" == "fury" ]]; then
  PIP_BIN=$(fury info -k full_pip_location 2>/dev/null)
  if [[ -z "$PIP_BIN" ]]; then
    echo "ERROR [aoc] cannot resolve the pip binary"
    exec 3>&-
    exit 1
  fi
  read -ra PIP_CMD <<< "$PIP_BIN"
  if [[ ! "${PIP_CMD[0]}" =~ ^/[a-zA-Z0-9._/-]+$ ]] \
    || [[ ${#PIP_CMD[@]} -gt 1 && "${PIP_CMD[*]:1}" != "-m pip" ]]; then
    echo "ERROR [aoc] full_pip_location has unexpected format"
    exec 3>&-
    exit 1
  fi

  # --index-url (not --extra-index-url): the private registry is the sole
  # source. --extra-index-url lets pip pick the highest version across BOTH
  # indexes, so a public PyPI package named cli-aoc could outrank ours and
  # get installed/executed here on every session start.
  if ! "${PIP_CMD[@]}" install \
      --index-url https://pypi.artifacts.furycloud.io/simple/ \
      "cli-aoc" --upgrade &>/dev/null; then
    if [[ "$NEEDS_INSTALL" == "true" ]]; then
      echo "ERROR [aoc] cli-aoc install failed"
      exec 3>&-
      exit 1
    fi
    # A usable fury runner can sync even if its opportunistic upgrade fails.
  fi
fi

# Resolve again after the install: pip put the package into the fury venv, so
# fury's plugin dispatch is normally available now.
if ! resolve_runner; then
  echo "ERROR [aoc] cli_aoc installed but neither 'fury aoc' nor 'aoc' responds"
  exec 3>&-
  exit 1
fi
echo "INFO [aoc] runner: ${AOC_CMD[*]} ($("${AOC_CMD[@]}" --version 2>&1 | head -1))"

# ── 2. Install/upgrade declared profiles ONLY ─────────────────────────────────
# `aoc profiles` diff-gates installs against the lock file, upgrades the
# declared profiles, and refreshes .agents/metadata/build/aoc-assets.json.
# It does NOT run context sync and does NOT create or update any context
# files (.agents/context.md, code-architecture.md, etc.).
PROFILES_EXIT=0
if "${AOC_CMD[@]}" profiles --provider "${AOC_PROVIDER:-claude}"; then
  echo "INFO [aoc] profiles install/upgrade completed"
else
  PROFILES_EXIT=$?
  echo "ERROR [aoc] profiles install/upgrade failed — see output above"
fi

# `profiles` does not emit the session signal (that is a `sync` feature), so
# emit the reload-skills signal ourselves on success so the agent picks up
# newly installed/updated skills without a manual /reload-skills.
if [[ "$PROFILES_EXIT" -eq 0 && "${AOC_PROVIDER:-claude}" == "claude" ]]; then
  cat >&3 <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "reloadSkills": true
  }
}
JSON
  echo "INFO [aoc] emitted reload-skills signal"
fi

exec 3>&-
exit "$PROFILES_EXIT"
