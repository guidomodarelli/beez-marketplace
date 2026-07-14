#!/bin/bash

# run-evals.sh — Central eval runner for the skill marketplace
# Runs with-skill vs baseline comparisons using eval-config.json
#
# Usage:
#   run-evals [path/to/skill]        Run evals for a specific skill
#   run-evals                         Run evals for skill in current directory
#   run-evals --all                   Run evals for all skills with eval-config.json
#   run-evals --jobs N [...]          Run N cases in parallel (default: 4, env: EVAL_JOBS)
#   run-evals --provider codex [...]  Run evals with Codex instead of auto-detecting
#
# Each skill only needs evals/eval-config.json — this script handles the rest.

set -e

# ── Colors ──────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Defaults ────────────────────────────────────────────
# Each job fires 2 concurrent agent calls (with-skill + baseline in parallel).
# Total concurrent API calls = EVAL_JOBS * 2. Lower EVAL_JOBS if rate-limited.
EVAL_JOBS="${EVAL_JOBS:-4}"
GROOT_MARKETPLACE_EVAL_MODEL="${GROOT_MARKETPLACE_EVAL_MODEL:-}"
# Machine-readable JSONL is the default so CI, tests, and real eval runs are
# reproducible and easy to parse. Use --pretty for the human-readable report.
EVAL_JSONL="${EVAL_JSONL:-1}"
GROOT_MARKETPLACE_EVAL_PROVIDER="${GROOT_MARKETPLACE_EVAL_PROVIDER:-auto}"
RESOLVED_EVAL_PROVIDER=""

# ── Resolve paths ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Functions ──────────────────────────────────────────

usage() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Skill Eval Runner${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    echo "Usage:"
    echo "  run-evals [path/to/skill]    Run evals for a specific skill"
    echo "  run-evals                    Run evals for skill in current directory"
    echo "  run-evals --all              Run evals for all skills with evals/"
    echo ""
    echo "Options:"
    echo "  --jobs N, -j N               Run N cases in parallel (default: 4)"
    echo "                               Each case runs 2 agent calls concurrently,"
    echo "                               so total API calls = N*2. Lower if rate-limited."
    echo "  --model M, -m M              Agent model to use (defaults: haiku for Claude,"
    echo "                               gpt-5.4-mini for Codex)"
    echo "                               Accepts aliases (haiku, sonnet, opus) or full model IDs."
    echo "                               Also configurable via GROOT_MARKETPLACE_EVAL_MODEL env var."
    echo "  --provider P                 Agent provider: auto, codex, or claude (default: auto)."
    echo "                               Also configurable via GROOT_MARKETPLACE_EVAL_PROVIDER env var."
    echo "  --jsonl, -J                  Emit machine-readable JSONL on stdout. This is"
    echo "                               the default and can also be set with EVAL_JSONL=1."
    echo "  --pretty, -P                 Emit the human-readable colored report instead"
    echo "                               of JSONL. Equivalent to EVAL_JSONL=0."
    echo ""
}

check_dependencies() {
    local missing=0

    resolve_eval_provider

    if ! command -v "$RESOLVED_EVAL_PROVIDER" &> /dev/null; then
        echo -e "${RED}ERROR: $RESOLVED_EVAL_PROVIDER CLI not found.${NC}"
        missing=1
    fi
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}ERROR: jq not found. Install with: brew install jq${NC}"
        missing=1
    fi
    if [ "$missing" -eq 1 ]; then
        exit 1
    fi
}

resolve_eval_provider() {
    case "$GROOT_MARKETPLACE_EVAL_PROVIDER" in
        claude|codex)
            RESOLVED_EVAL_PROVIDER="$GROOT_MARKETPLACE_EVAL_PROVIDER"
            ;;
        auto)
            if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ] || [ -n "${CODEX_HOME:-}" ]; then
                if command -v codex &> /dev/null; then
                    RESOLVED_EVAL_PROVIDER="codex"
                fi
            fi
            if [ -z "$RESOLVED_EVAL_PROVIDER" ] && { [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SSE_PORT:-}" ]; }; then
                if command -v claude &> /dev/null; then
                    RESOLVED_EVAL_PROVIDER="claude"
                fi
            fi
            if [ -z "$RESOLVED_EVAL_PROVIDER" ] && command -v claude &> /dev/null; then
                RESOLVED_EVAL_PROVIDER="claude"
            fi
            if [ -z "$RESOLVED_EVAL_PROVIDER" ] && command -v codex &> /dev/null; then
                RESOLVED_EVAL_PROVIDER="codex"
            fi
            [ -n "$RESOLVED_EVAL_PROVIDER" ] || RESOLVED_EVAL_PROVIDER="claude"
            ;;
        *)
            echo -e "${RED}ERROR: Invalid provider '$GROOT_MARKETPLACE_EVAL_PROVIDER'. Use auto, codex, or claude.${NC}" >&2
            exit 1
            ;;
    esac

    if [ -z "$GROOT_MARKETPLACE_EVAL_MODEL" ]; then
        case "$RESOLVED_EVAL_PROVIDER" in
            codex) GROOT_MARKETPLACE_EVAL_MODEL="gpt-5.4-mini" ;;
            *) GROOT_MARKETPLACE_EVAL_MODEL="haiku" ;;
        esac
    fi
}

run_agent_prompt() {
    local cwd="$1"
    local input="$2"
    local output_file="$3"
    local codex_home="${4:-}"

    case "$RESOLVED_EVAL_PROVIDER" in
        claude)
            (cd "$cwd" && env -u CLAUDECODE claude -p "$input" \
                --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
                --setting-sources project \
                --allowedTools "Bash(read_only:true),Read,Glob,Grep") \
                > "$output_file" 2>&1
            ;;
        codex)
            local event_stream_file
            event_stream_file=$(mktemp)

            CODEX_HOME="$codex_home" codex exec \
                --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
                --cd "$cwd" \
                --skip-git-repo-check \
                --ephemeral \
                --ignore-rules \
                --sandbox read-only \
                --color never \
                --json \
                "$input" \
                < /dev/null \
                > "$event_stream_file" 2>&1

            jq -Rsr '
                split("\n")
                | map(
                    fromjson?
                    | select(.type == "item.completed" and .item.type == "agent_message")
                    | .item.text
                )
                | last // ""
            ' "$event_stream_file" > "$output_file"

            if [ ! -s "$output_file" ] || ! grep -q '[^[:space:]]' "$output_file"; then
                cp "$event_stream_file" "$output_file"
            fi

            rm -f "$event_stream_file"
            ;;
    esac
}

create_codex_eval_home() {
    local target_home="$1"
    local source_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
    local source_home
    source_home="$(cd "$(dirname "$source_config")" 2>/dev/null && pwd || dirname "$source_config")"

    mkdir -p "$target_home/skills" "$target_home/plugins" "$target_home/marketplaces"

    if [ -f "$source_config" ]; then
        awk '
            BEGIN { keep = 0 }
            /^model[[:space:]]*=/ || /^model_provider[[:space:]]*=/ || /^model_reasoning_effort[[:space:]]*=/ {
                print
                next
            }
            /^\[model_providers\./ {
                keep = 1
                print
                next
            }
            /^\[/ {
                keep = 0
            }
            keep {
                print
            }
        ' "$source_config" > "$target_home/config.toml"
    fi

    local auth_file
    for auth_file in \
        "$source_home"/auth.json \
        "$source_home"/credentials.json \
        "$source_home"/.codex-auth.json \
        "$source_home"/state_*.sqlite \
        "$source_home"/state_*.sqlite-shm \
        "$source_home"/state_*.sqlite-wal; do
        if [ -e "$auth_file" ]; then
            cp -p "$auth_file" "$target_home/" 2>/dev/null || true
        fi
    done
}

preflight_eval_provider() {
    local check_cwd
    local output_file
    check_cwd=$(mktemp -d)
    output_file=$(mktemp)

    local codex_home=""
    if [ "$RESOLVED_EVAL_PROVIDER" = "codex" ]; then
        codex_home=$(mktemp -d)
        create_codex_eval_home "$codex_home"
    fi

    if ! run_agent_prompt "$check_cwd" "Reply exactly: eval-provider-ready" "$output_file" "$codex_home"; then
        echo -e "${RED}ERROR: $RESOLVED_EVAL_PROVIDER provider preflight failed.${NC}" >&2
        echo "The selected provider did not complete a minimal eval prompt." >&2
        echo "Check authentication and provider configuration before running evals." >&2
        if [ "$RESOLVED_EVAL_PROVIDER" = "codex" ]; then
            echo "For Codex, verify $HOME/.codex/config.toml, auth, and proxy settings." >&2
        fi
        echo "No fallback provider was used; set --provider claude or GROOT_MARKETPLACE_EVAL_PROVIDER=claude explicitly if that is intended." >&2
        echo "Preflight output:" >&2
        sed -n '1,40p' "$output_file" >&2
        rm -rf "$check_cwd" "$output_file" "$codex_home"
        return 1
    fi

    if ! grep -qi 'eval-provider-ready' "$output_file"; then
        echo -e "${RED}ERROR: $RESOLVED_EVAL_PROVIDER provider preflight returned an unexpected response.${NC}" >&2
        echo "No eval cases were run. Check provider configuration and model availability." >&2
        echo "Preflight output:" >&2
        sed -n '1,40p' "$output_file" >&2
        rm -rf "$check_cwd" "$output_file" "$codex_home"
        return 1
    fi

    rm -rf "$check_cwd" "$output_file" "$codex_home"
    return 0
}

find_eval_config() {
    local skill_path="$1"

    # Check evals/eval-config.json
    if [ -f "$skill_path/evals/eval-config.json" ]; then
        echo "$skill_path/evals/eval-config.json"
        return 0
    fi

    echo ""
    return 1
}

validate_assertion_contains() {
    local response="$1"
    local value="$2"
    if echo "$response" | grep -qi "$value"; then
        return 0
    fi
    return 1
}

validate_assertion_contains_any() {
    local response="$1"
    local config_file="$2"
    local case_idx="$3"
    local assert_idx="$4"

    local values_count
    values_count=$(jq ".test_cases[$case_idx].assertions[$assert_idx].values | length" "$config_file")

    for k in $(seq 0 $((values_count - 1))); do
        local v
        v=$(jq -r ".test_cases[$case_idx].assertions[$assert_idx].values[$k]" "$config_file")
        if echo "$response" | grep -qi "$v"; then
            return 0
        fi
    done
    return 1
}

validate_assertion_not_contains_any() {
    local response="$1"
    local config_file="$2"
    local case_idx="$3"
    local assert_idx="$4"

    local values_count
    values_count=$(jq ".test_cases[$case_idx].assertions[$assert_idx].values | length" "$config_file")

    for k in $(seq 0 $((values_count - 1))); do
        local v
        v=$(jq -r ".test_cases[$case_idx].assertions[$assert_idx].values[$k]" "$config_file")
        if echo "$response" | grep -qi "$v"; then
            return 1
        fi
    done
    return 0
}

validate_assertion_regex() {
    local response="$1"
    local pattern="$2"
    if echo "$response" | grep -qiE "$pattern"; then
        return 0
    fi
    return 1
}

# Records a failed assertion as one JSON object into the failures file (if set),
# so the JSONL report can list exactly which assertions broke and why.
record_failure() {
    local failures_file="$1"
    local type="$2"
    local desc="$3"
    local detail="$4"
    [ -n "$failures_file" ] || return 0
    jq -nc --arg type "$type" --arg description "$desc" --arg detail "$detail" \
        '{type: $type, description: $description, detail: $detail}' >> "$failures_file"
}

read_failures_json() {
    local failures_file="$1"

    if [ -f "$failures_file" ] && [ -s "$failures_file" ]; then
        jq -cs '.' "$failures_file" 2>/dev/null || printf '[]'
        return 0
    fi

    printf '[]'
}

write_case_result_jsonl() {
    local result_dir="$1"
    local case_idx="$2"
    local skill_name="$3"
    local id="$4"
    local description="$5"
    local input="$6"
    local total="$7"
    local status_str="$8"
    local elapsed="$9"
    local failed_json="${10}"
    local workspace="${11}"

    jq -nc \
        --arg skill "$skill_name" \
        --arg provider "$RESOLVED_EVAL_PROVIDER" \
        --arg id "$id" \
        --arg description "$description" \
        --arg input "$input" \
        --argjson index "$((case_idx + 1))" \
        --argjson total "$total" \
        --arg status "$status_str" \
        --argjson duration "$elapsed" \
        --argjson failed "$failed_json" \
        --arg with_skill "$workspace/with-skill/$id.txt" \
        --arg baseline "$workspace/without-skill/$id.txt" \
        '{event: "case", provider: $provider, skill: $skill, id: $id, description: $description, input: $input, index: $index, total: $total, status: $status, duration_seconds: $duration, failed_assertions: $failed, artifacts: {with_skill: $with_skill, baseline: $baseline}}' \
        > "$result_dir/$case_idx.jsonl"
}

record_case_setup_failure() {
    local result_dir="$1"
    local case_idx="$2"
    local skill_name="$3"
    local id="$4"
    local description="$5"
    local input="$6"
    local total="$7"
    local workspace="$8"
    local detail="$9"
    local elapsed="${10}"
    local failed_json

    failed_json=$(jq -nc --arg detail "$detail" \
        '[{type: "infrastructure", description: "Eval runner failed before executing case", detail: $detail}]')
    printf '1\n' > "$result_dir/$case_idx.txt"
    write_case_result_jsonl "$result_dir" "$case_idx" "$skill_name" "$id" "$description" "$input" "$total" "failed" "$elapsed" "$failed_json" "$workspace"
}

run_assertions() {
    local response="$1"
    local config_file="$2"
    local case_idx="$3"
    local failures_file="$4"
    local case_passed=true

    local assertion_count
    assertion_count=$(jq ".test_cases[$case_idx].assertions | length" "$config_file")

    for j in $(seq 0 $((assertion_count - 1))); do
        local type desc
        type=$(jq -r ".test_cases[$case_idx].assertions[$j].type" "$config_file")
        desc=$(jq -r ".test_cases[$case_idx].assertions[$j].description // \"\"" "$config_file")

        case "$type" in
            contains)
                local value
                value=$(jq -r ".test_cases[$case_idx].assertions[$j].value" "$config_file")
                if validate_assertion_contains "$response" "$value"; then
                    echo -e "  ${GREEN}✅ $desc${NC}"
                else
                    echo -e "  ${RED}❌ $desc${NC} (expected: '$value')"
                    case_passed=false
                    record_failure "$failures_file" "$type" "$desc" "expected to contain: $value"
                fi
                ;;

            contains_any)
                if validate_assertion_contains_any "$response" "$config_file" "$case_idx" "$j"; then
                    echo -e "  ${GREEN}✅ $desc${NC}"
                else
                    echo -e "  ${RED}❌ $desc${NC}"
                    case_passed=false
                    local values
                    values=$(jq -c ".test_cases[$case_idx].assertions[$j].values" "$config_file")
                    record_failure "$failures_file" "$type" "$desc" "expected to contain any of: $values"
                fi
                ;;

            not_contains_any)
                if validate_assertion_not_contains_any "$response" "$config_file" "$case_idx" "$j"; then
                    echo -e "  ${GREEN}✅ $desc${NC}"
                else
                    echo -e "  ${RED}❌ $desc${NC} (found unwanted content)"
                    case_passed=false
                    local values
                    values=$(jq -c ".test_cases[$case_idx].assertions[$j].values" "$config_file")
                    record_failure "$failures_file" "$type" "$desc" "found unwanted content from: $values"
                fi
                ;;

            regex)
                local pattern
                pattern=$(jq -r ".test_cases[$case_idx].assertions[$j].pattern" "$config_file")
                if validate_assertion_regex "$response" "$pattern"; then
                    echo -e "  ${GREEN}✅ $desc${NC}"
                else
                    echo -e "  ${RED}❌ $desc${NC} (pattern: '$pattern')"
                    case_passed=false
                    record_failure "$failures_file" "$type" "$desc" "did not match pattern: $pattern"
                fi
                ;;

            *)
                echo -e "  ${YELLOW}⚠ Unknown assertion type: $type${NC}"
                ;;
        esac
    done

    if [ "$case_passed" = true ]; then
        return 0
    fi
    return 1
}

# Runs a single eval case in isolation; all output buffered to a file.
# Called as a background job by run_skill_evals.
# output_dir and result_dir are passed explicitly so stale jobs from interrupted
# runs hold their old paths — if those dirs were cleaned up, the guard below exits early.
run_single_case() {
    local i="$1"
    local config_file="$2"
    local workspace="$3"
    local total="$4"
    local output_dir="$5"
    local result_dir="$6"
    local skill_cwd="$7"
    local baseline_cwd="$8"
    local skill_codex_home="$9"
    local baseline_codex_home="${10}"

    local id input description skill_name
    id=$(jq -r ".test_cases[$i].id" "$config_file")
    input=$(jq -r ".test_cases[$i].input" "$config_file")
    description=$(jq -r ".test_cases[$i].description" "$config_file")
    skill_name=$(jq -r '.skill' "$config_file")
    local start_time=$SECONDS

    # Per-case file collecting failed-assertion JSON objects (one per line).
    local failures_file="$result_dir/$i.failures"
    mkdir -p "$result_dir" || {
        echo "ERROR: Case setup failed: could not create result directory: $result_dir" >&2
        return 1
    }
    touch "$failures_file" || {
        local setup_elapsed=$(( SECONDS - start_time ))
        echo "ERROR: Case setup failed: could not create failures file: $failures_file" >&2
        record_case_setup_failure "$result_dir" "$i" "$skill_name" "$id" "$description" "$input" "$total" "$workspace" "could not create failures file: $failures_file" "$setup_elapsed"
        echo -e "  ${RED}❌ [$((i + 1))/$total] $id${NC}  ${setup_elapsed}s (infrastructure failure)" >&2
        return 0
    }

    {
        echo "─────────────────────────────────────────"
        echo -e "${BOLD}CASE [$((i + 1))/$total]: $id${NC}"
        echo "DESC: $description"
        echo "INPUT: $input"
        echo ""

        # Fire both agent calls in parallel; responses land in workspace files.
        # skill_cwd has provider-specific project skills; baseline_cwd has none.
        # baseline_cwd is empty — no skills at all.
        run_agent_prompt "$skill_cwd" "$input" "$workspace/with-skill/$id.txt" "$skill_codex_home" &
        local pid_with=$!

        run_agent_prompt "$baseline_cwd" "$input" "$workspace/without-skill/$id.txt" "$baseline_codex_home" &
        local pid_base=$!

        wait $pid_with || true
        wait $pid_base || true

        local response_with response_base
        response_with=$(cat "$workspace/with-skill/$id.txt" || echo "ERROR")
        response_base=$(cat "$workspace/without-skill/$id.txt" || echo "ERROR")

        # With skill
        echo -e "→ ${BLUE}[WITH SKILL]${NC}"
        echo "$response_with" | head -30
        echo ""

        # Baseline
        echo -e "→ ${BLUE}[BASELINE]${NC}"
        echo "$response_base" | head -30
        echo ""

        # Assertions
        if run_assertions "$response_with" "$config_file" "$i" "$failures_file"; then
            echo ""
            echo -e "  ${GREEN}RESULT: ✅ PASSED${NC}"
            echo "0" > "$result_dir/$i.txt"
        else
            echo ""
            echo -e "  ${RED}RESULT: ❌ FAILED${NC}"
            echo "1" > "$result_dir/$i.txt"
        fi
        echo ""
    } > "$output_dir/$i.txt" 2>&1

    # Guard: if our output file doesn't exist, this is a stale job from a previous
    # interrupted run whose dirs were already cleaned up — suppress the completion notice.
    [ -f "$output_dir/$i.txt" ] || return 0

    # Completion count = number of result files written so far (including this one)
    local done_count
    done_count=$(ls "$result_dir"/*.txt 2>/dev/null | wc -l | tr -d ' ')

    local elapsed=$(( SECONDS - start_time ))
    local duration
    if [ "$elapsed" -ge 60 ]; then
        duration="${elapsed}s ($(( elapsed / 60 ))m $(( elapsed % 60 ))s)"
    else
        duration="${elapsed}s"
    fi

    local result
    result=$(cat "$result_dir/$i.txt" 2>/dev/null || echo "1")

    # Build the per-case JSONL line (consumed in the print phase when --jsonl is set).
    local status_str="passed"
    [ "$result" -eq 0 ] || status_str="failed"
    local failed_json
    failed_json=$(read_failures_json "$failures_file")
    write_case_result_jsonl "$result_dir" "$i" "$skill_name" "$id" "$description" "$input" "$total" "$status_str" "$elapsed" "$failed_json" "$workspace"

    if [ "$result" -eq 0 ]; then
        echo -e "  ${GREEN}✅ [$done_count/$total] $id${NC}  ${duration}" >&2
    else
        echo -e "  ${RED}❌ [$done_count/$total] $id${NC}  ${duration}" >&2
    fi
}

run_skill_evals() {
    local skill_path="$1"
    local config_file
    config_file=$(find_eval_config "$skill_path")

    if [ -z "$config_file" ]; then
        echo -e "${YELLOW}⚠ No eval-config.json found in $skill_path/evals/${NC}"
        return 1
    fi

    local skill_name
    skill_name=$(jq -r '.skill' "$config_file")
    local total
    total=$(jq '.test_cases | length' "$config_file")

    # Persistent workspace for reviewable artifacts; ephemeral subdirs are per-invocation
    # (named by $$) so stale background jobs from interrupted runs write to their own
    # old dirs, not ours. All previous run dirs are wiped at start.
    local workspace="$REPO_ROOT/.eval-results/$skill_name"
    local output_dir="$workspace/case-output-$$"
    local result_dir="$workspace/case-results-$$"
    mkdir -p "$workspace/with-skill" "$workspace/without-skill"
    rm -rf "$workspace"/case-output-* "$workspace"/case-results-*
    mkdir -p "$output_dir" "$result_dir"

    # Shared temp dirs: with-skill has the skill symlinked for both supported
    # providers; baseline is a plain empty dir with no project-local skills.
    local skill_cwd baseline_cwd skill_codex_home baseline_codex_home
    skill_cwd=$(mktemp -d)
    baseline_cwd=$(mktemp -d)
    mkdir -p "$skill_cwd/.claude/skills"
    ln -s "$(cd "$skill_path" && pwd)" "$skill_cwd/.claude/skills/$skill_name"
    mkdir -p "$skill_cwd/.codex/skills"
    ln -s "$(cd "$skill_path" && pwd)" "$skill_cwd/.codex/skills/$skill_name"
    skill_codex_home=""
    baseline_codex_home=""
    if [ "$RESOLVED_EVAL_PROVIDER" = "codex" ]; then
        skill_codex_home=$(mktemp -d)
        baseline_codex_home=$(mktemp -d)
        create_codex_eval_home "$skill_codex_home"
        create_codex_eval_home "$baseline_codex_home"
        ln -s "$(cd "$skill_path" && pwd)" "$skill_codex_home/skills/$skill_name"
    fi
    trap "rm -rf '$skill_cwd' '$baseline_cwd' '$skill_codex_home' '$baseline_codex_home'" RETURN

    local suite_start=$SECONDS

    # In JSONL mode keep stdout pure (data only): send the human header to stderr.
    local header_fd=1
    [ "$EVAL_JSONL" = "1" ] && header_fd=2
    {
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Evaluations: ${BOLD}$skill_name${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Config:    $config_file"
        echo -e "  Skill:     $skill_path"
        echo -e "  Cases:     $total"
        echo -e "  Jobs:      $EVAL_JOBS (parallel)"
        echo -e "  Model:     $GROOT_MARKETPLACE_EVAL_MODEL"
        echo -e "  Provider:  $RESOLVED_EVAL_PROVIDER"
        echo -e "  Results:   $workspace"
        echo ""
    } >&"$header_fd"

    # ── Dispatch phase: spawn cases in parallel, pool-limited ──
    local pids=()
    for i in $(seq 0 $((total - 1))); do
        # Drain finished PIDs until pool has room
        while [ ${#pids[@]} -ge "$EVAL_JOBS" ]; do
            local running=()
            for pid in "${pids[@]}"; do
                kill -0 "$pid" 2>/dev/null && running+=("$pid")
            done
            pids=("${running[@]}")
            [ ${#pids[@]} -ge "$EVAL_JOBS" ] && sleep 0.2
        done

        run_single_case "$i" "$config_file" "$workspace" "$total" "$output_dir" "$result_dir" "$skill_cwd" "$baseline_cwd" "$skill_codex_home" "$baseline_codex_home" &
        pids+=($!)
    done

    # Wait for all remaining jobs (|| true: pass/fail handled via result files)
    wait || true

    # ── Print phase: output in original order, aggregate counts ──
    if [ "$EVAL_JSONL" != "1" ]; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Case Results: ${BOLD}$skill_name${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
    fi
    local passed=0
    local failed=0
    for i in $(seq 0 $((total - 1))); do
        if [ ! -f "$result_dir/$i.txt" ]; then
            mkdir -p "$result_dir" 2>/dev/null || true
            local missing_id missing_input missing_description missing_elapsed missing_failed_json
            missing_id=$(jq -r ".test_cases[$i].id" "$config_file")
            missing_input=$(jq -r ".test_cases[$i].input" "$config_file")
            missing_description=$(jq -r ".test_cases[$i].description" "$config_file")
            missing_elapsed=$(( SECONDS - suite_start ))
            missing_failed_json=$(jq -nc \
                '[{type: "infrastructure", description: "Eval runner did not write a case result", detail: "case finished before writing result files"}]')
            printf '1\n' > "$result_dir/$i.txt" 2>/dev/null || true
            write_case_result_jsonl "$result_dir" "$i" "$skill_name" "$missing_id" "$missing_description" "$missing_input" "$total" "failed" "$missing_elapsed" "$missing_failed_json" "$workspace" 2>/dev/null || true
        fi
        if [ "$EVAL_JSONL" = "1" ]; then
            cat "$result_dir/$i.jsonl" 2>/dev/null || true
        else
            cat "$output_dir/$i.txt"
        fi
        local result
        result=$(cat "$result_dir/$i.txt" 2>/dev/null || echo "1")
        if [ "$result" -eq 0 ]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Summary
    local suite_elapsed=$(( SECONDS - suite_start ))
    local suite_duration
    if [ "$suite_elapsed" -ge 60 ]; then
        suite_duration="${suite_elapsed}s ($(( suite_elapsed / 60 ))m $(( suite_elapsed % 60 ))s)"
    else
        suite_duration="${suite_elapsed}s"
    fi

    if [ "$EVAL_JSONL" = "1" ]; then
        jq -nc \
            --arg skill "$skill_name" \
            --arg provider "$RESOLVED_EVAL_PROVIDER" \
            --argjson total "$total" \
            --argjson passed "$passed" \
            --argjson failed "$failed" \
            --argjson duration "$suite_elapsed" \
            '{event: "summary", provider: $provider, skill: $skill, total: $total, passed: $passed, failed: $failed, duration_seconds: $duration}'
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Summary: ${BOLD}$skill_name${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Total:   $total"
        echo -e "  Passed:  ${GREEN}$passed ✅${NC}"
        echo -e "  Failed:  ${RED}$failed ❌${NC}"
        echo -e "  Time:    $suite_duration"
        echo ""

        if [ "$failed" -gt 0 ]; then
            echo -e "  ${YELLOW}Review failed cases in: $workspace/with-skill/${NC}"
        fi
    fi

    if [ "$failed" -gt 0 ]; then
        return 1
    fi
    return 0
}

run_all_evals() {
    # In JSONL mode keep stdout pure: decorative banners go to stderr.
    local banner_fd=1
    [ "$EVAL_JSONL" = "1" ] && banner_fd=2
    {
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Running ALL skill evals${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
    } >&"$banner_fd"

    local total_skills=0
    local passed_skills=0
    local failed_skills=0

    # Search in skills/ and plugins/
    for dir in "$REPO_ROOT"/skills/*/evals "$REPO_ROOT"/plugins/*/skills/*/evals; do
        [ -d "$dir" ] || continue
        [ -f "$dir/eval-config.json" ] || continue

        local skill_path
        skill_path=$(dirname "$dir")
        total_skills=$((total_skills + 1))

        if run_skill_evals "$skill_path"; then
            passed_skills=$((passed_skills + 1))
        else
            failed_skills=$((failed_skills + 1))
        fi
        [ "$EVAL_JSONL" = "1" ] || echo ""
    done

    if [ "$total_skills" -eq 0 ]; then
        echo -e "${YELLOW}No skills with evals/eval-config.json found.${NC}" >&"$banner_fd"
        return 0
    fi

    if [ "$EVAL_JSONL" = "1" ]; then
        jq -nc \
            --argjson skills "$total_skills" \
            --argjson all_passed "$passed_skills" \
            --argjson with_failures "$failed_skills" \
            '{event: "global_summary", skills_evaluated: $skills, all_passed: $all_passed, with_failures: $with_failures}'
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Global Summary${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Skills evaluated: $total_skills"
        echo -e "  All passed:       ${GREEN}$passed_skills ✅${NC}"
        echo -e "  With failures:    ${RED}$failed_skills ❌${NC}"
        echo ""
    fi

    if [ "$failed_skills" -gt 0 ]; then
        return 1
    fi
    return 0
}

has_eval_targets() {
    local dir
    for dir in "$REPO_ROOT"/skills/*/evals "$REPO_ROOT"/plugins/*/skills/*/evals; do
        [ -d "$dir" ] || continue
        [ -f "$dir/eval-config.json" ] || continue
        return 0
    done
    return 1
}

target_requires_provider() {
    case "${1:-}" in
        --all)
            has_eval_targets
            ;;
        "")
            if [ -f "SKILL.md" ] || [ -f "../SKILL.md" ]; then
                return 0
            fi
            echo -e "${RED}ERROR: No SKILL.md found in current directory.${NC}"
            echo "Run from a skill directory or pass the path: run-evals path/to/skill"
            exit 1
            ;;
        *)
            if [ -d "$1" ]; then
                return 0
            fi
            echo -e "${RED}ERROR: Directory not found: $1${NC}"
            exit 1
            ;;
    esac
}

# ── Main ───────────────────────────────────────────────

# Help doesn't need dependencies
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
esac

# Pre-parse --jobs / -j (may appear anywhere in args)
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --jobs|-j)
            EVAL_JOBS="$2"
            shift 2
            ;;
        --model|-m)
            GROOT_MARKETPLACE_EVAL_MODEL="$2"
            shift 2
            ;;
        --provider)
            GROOT_MARKETPLACE_EVAL_PROVIDER="$2"
            shift 2
            ;;
        --jsonl|-J)
            EVAL_JSONL=1
            shift
            ;;
        --pretty|-P)
            EVAL_JSONL=0
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

if target_requires_provider "$@"; then
    check_dependencies
    preflight_eval_provider
fi

case "${1:-}" in
    --all)
        run_all_evals
        ;;
    "")
        # No args — look for skill in current directory
        if [ -f "SKILL.md" ]; then
            run_skill_evals "$(pwd)"
        elif [ -f "../SKILL.md" ]; then
            # Inside evals/ directory
            run_skill_evals "$(cd .. && pwd)"
        else
            echo -e "${RED}ERROR: No SKILL.md found in current directory.${NC}"
            echo "Run from a skill directory or pass the path: run-evals path/to/skill"
            exit 1
        fi
        ;;
    *)
        # Path to skill provided
        if [ -d "$1" ]; then
            run_skill_evals "$1"
        else
            echo -e "${RED}ERROR: Directory not found: $1${NC}"
            exit 1
        fi
        ;;
esac
