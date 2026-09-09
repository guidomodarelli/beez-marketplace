EVAL_RUNNER="${BATS_TEST_DIRNAME}/../run-evals.sh"

setup_eval_runner_fixture() {
    TEST_ROOT="${BATS_TEST_TMPDIR}/eval-runner-${BATS_TEST_NUMBER}"
    STUB_BIN="${TEST_ROOT}/bin"
    SKILL_NAME="contract-skill-${BATS_TEST_NUMBER}"
    SKILL_DIR="${TEST_ROOT}/${SKILL_NAME}"
    CLAUDE_ARGS_LOG="${TEST_ROOT}/claude-args.log"

    mkdir -p "${STUB_BIN}" "${SKILL_DIR}/evals"
    : > "${CLAUDE_ARGS_LOG}"

    cat > "${SKILL_DIR}/SKILL.md" <<SKILL
---
name: ${SKILL_NAME}
description: Contract skill for eval runner environment tests.
---

# Contract Skill
SKILL

    cat > "${SKILL_DIR}/evals/eval-config.json" <<JSON
{
  "skill": "${SKILL_NAME}",
  "test_cases": [
    {
      "id": "contract",
      "description": "runner contract",
      "input": "Reply ok",
      "assertions": [
        {
          "type": "contains",
          "value": "ok"
        }
      ]
    }
  ]
}
JSON

    cat > "${STUB_BIN}/claude" <<'CLAUDE_STUB'
#!/bin/bash

case "$*" in
  *eval-provider-ready*)
    printf 'eval-provider-ready\n'
    ;;
  *)
    printf '%s\n' "$*" >> "$CLAUDE_ARGS_LOG"
    if [[ -n "${CLAUDE_RESPONSE_FILE:-}" ]]; then
      cat "$CLAUDE_RESPONSE_FILE"
    else
      printf 'ok\n'
    fi
    ;;
esac
CLAUDE_STUB
    chmod +x "${STUB_BIN}/claude"
}

install_failures_touch_stub() {
    cat > "${STUB_BIN}/touch" <<'TOUCH_STUB'
#!/bin/bash

case "$1" in
  *.failures)
    exit 1
    ;;
  *)
    /usr/bin/touch "$@"
    ;;
esac
TOUCH_STUB
    chmod +x "${STUB_BIN}/touch"
}

run_eval_runner() {
    local environment=(
        "PATH=${STUB_BIN}:${PATH}"
        "CLAUDE_ARGS_LOG=${CLAUDE_ARGS_LOG}"
        "GROOT_MARKETPLACE_EVAL_PROVIDER=claude"
    )

    if [[ -n "${GROOT_MARKETPLACE_EVAL_MODEL:-}" ]]; then
        environment+=("GROOT_MARKETPLACE_EVAL_MODEL=${GROOT_MARKETPLACE_EVAL_MODEL}")
    fi
    if [[ -n "${CLAUDE_RESPONSE_FILE:-}" ]]; then
        environment+=("CLAUDE_RESPONSE_FILE=${CLAUDE_RESPONSE_FILE}")
    fi

    run --separate-stderr env "${environment[@]}" \
        "${EVAL_RUNNER}" --jobs 1 "$@" "${SKILL_DIR}"
}
