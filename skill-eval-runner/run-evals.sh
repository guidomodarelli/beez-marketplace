#!/bin/bash

# run-evals.sh — Central eval runner for the skill marketplace
# Runs with-skill vs baseline comparisons using eval-config.json
#
# Usage:
#   run-evals [path/to/skill]        Run evals for a specific skill
#   run-evals                         Run evals for skill in current directory
#   run-evals --all                   Run evals for all skills with eval-config.json
#   run-evals --jobs N [...]          Run N cases in parallel (default: 4, env: EVAL_JOBS)
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
# Each job fires 2 concurrent claude -p calls (with-skill + baseline in parallel).
# Total concurrent API calls = EVAL_JOBS * 2. Lower EVAL_JOBS if rate-limited.
EVAL_JOBS="${EVAL_JOBS:-4}"
EVAL_MODEL="${EVAL_MODEL:-haiku}"
# When 1, emit machine-readable JSONL on stdout (one object per case + a summary
# object) instead of the human-readable colored report. See --jsonl.
EVAL_JSONL="${EVAL_JSONL:-0}"

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
    echo "                               Each case runs 2 claude calls concurrently,"
    echo "                               so total API calls = N*2. Lower if rate-limited."
    echo "  --model M, -m M              Claude model to use (default: haiku)"
    echo "                               Accepts aliases (haiku, sonnet, opus) or full model IDs."
    echo "                               Also configurable via EVAL_MODEL env var."
    echo "  --jsonl, -J                  Emit machine-readable JSONL on stdout instead of"
    echo "                               the colored report: one {\"event\":\"case\",...} object"
    echo "                               per case (with failed_assertions) and a final"
    echo "                               {\"event\":\"summary\",...} object. Also via EVAL_JSONL=1."
    echo ""
}

check_dependencies() {
    local missing=0
    if ! command -v claude &> /dev/null; then
        echo -e "${RED}ERROR: claude CLI not found.${NC}"
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

    local id input description skill_name
    id=$(jq -r ".test_cases[$i].id" "$config_file")
    input=$(jq -r ".test_cases[$i].input" "$config_file")
    description=$(jq -r ".test_cases[$i].description" "$config_file")
    skill_name=$(jq -r '.skill' "$config_file")

    # Per-case file collecting failed-assertion JSON objects (one per line).
    local failures_file="$result_dir/$i.failures"
    : > "$failures_file"

    local start_time=$SECONDS
    {
        echo "─────────────────────────────────────────"
        echo -e "${BOLD}CASE [$((i + 1))/$total]: $id${NC}"
        echo "DESC: $description"
        echo "INPUT: $input"
        echo ""

        # Fire both claude calls in parallel; responses land in workspace files.
        # --setting-sources project loads only from the cwd's .claude/, not ~/.claude/,
        # so global skills don't interfere with the skill under test.
        # skill_cwd has .claude/skills/<name>/ — only the tested skill is loaded.
        # baseline_cwd is empty — no skills at all.
        (cd "$skill_cwd" && env -u CLAUDECODE claude -p "$input" \
            --model "$EVAL_MODEL" \
            --setting-sources project \
            --allowedTools "Bash(read_only:true),Read,Glob,Grep") \
            > "$workspace/with-skill/$id.txt" 2>&1 &
        local pid_with=$!

        (cd "$baseline_cwd" && env -u CLAUDECODE claude -p "$input" \
            --model "$EVAL_MODEL" \
            --setting-sources project \
            --allowedTools "Bash(read_only:true),Read,Glob,Grep") \
            > "$workspace/without-skill/$id.txt" 2>&1 &
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
    local failed_json="[]"
    [ -s "$failures_file" ] && failed_json=$(jq -cs '.' "$failures_file")
    jq -nc \
        --arg skill "$skill_name" \
        --arg id "$id" \
        --argjson index "$((i + 1))" \
        --argjson total "$total" \
        --arg status "$status_str" \
        --argjson duration "$elapsed" \
        --argjson failed "$failed_json" \
        '{event: "case", skill: $skill, id: $id, index: $index, total: $total, status: $status, duration_seconds: $duration, failed_assertions: $failed}' \
        > "$result_dir/$i.jsonl"

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

    # Shared temp dirs for claude -p cwd: with-skill has the skill symlinked,
    # baseline is a plain empty dir (no .claude/skills — no skill loaded)
    local skill_cwd baseline_cwd
    skill_cwd=$(mktemp -d)
    baseline_cwd=$(mktemp -d)
    mkdir -p "$skill_cwd/.claude/skills"
    ln -s "$(cd "$skill_path" && pwd)" "$skill_cwd/.claude/skills/$skill_name"
    trap "rm -rf '$skill_cwd' '$baseline_cwd'" RETURN

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
        echo -e "  Model:     $EVAL_MODEL"
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

        run_single_case "$i" "$config_file" "$workspace" "$total" "$output_dir" "$result_dir" "$skill_cwd" "$baseline_cwd" &
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
            --argjson total "$total" \
            --argjson passed "$passed" \
            --argjson failed "$failed" \
            --argjson duration "$suite_elapsed" \
            '{event: "summary", skill: $skill, total: $total, passed: $passed, failed: $failed, duration_seconds: $duration}'
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
            EVAL_MODEL="$2"
            shift 2
            ;;
        --jsonl|-J)
            EVAL_JSONL=1
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

check_dependencies

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
