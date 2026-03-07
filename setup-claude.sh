#!/bin/bash
# ============================================================================
# Claude Code Environment Bootstrap
# ============================================================================
# Replicates Q's preferred Claude Code setup on any new machine/project.
#
# Usage:
#   # Full setup (global + project):
#   bash setup-claude.sh
#
#   # Global only (no project-level setup):
#   bash setup-claude.sh --global-only
#
#   # Project only (assumes global already done):
#   bash setup-claude.sh --project-only
# ============================================================================

set -euo pipefail

MODE="${1:-full}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PROJECT_CLAUDE=".claude"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

# ============================================================================
# GLOBAL SETUP (~/.claude/)
# ============================================================================
setup_global() {
    info "Setting up global Claude Code config..."
    mkdir -p "$CLAUDE_HOME"

    # --- Global settings.json (clean permissions + plugins + statusline) ---
    if [[ -f "$CLAUDE_HOME/settings.json" ]]; then
        cp "$CLAUDE_HOME/settings.json" "$CLAUDE_HOME/settings.json.bak.$(date +%Y%m%d_%H%M%S)"
        warn "Backed up existing settings.json"
    fi

    cat > "$CLAUDE_HOME/settings.json" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "Bash(ls:*)",
      "Bash(python:*)",
      "Bash(python3:*)",
      "Bash(pytest:*)",
      "Bash(pip:*)",
      "Bash(pip3:*)",
      "Bash(pip show:*)",
      "Bash(lsof:*)",
      "Bash(kill:*)",
      "Bash(killall:*)",
      "Bash(ip:*)",
      "Bash(awk:*)",
      "Bash(sed:*)",
      "Bash(wc:*)",
      "Bash(sort:*)",
      "Bash(uniq:*)",
      "Bash(node:*)",
      "Bash(npm:*)",
      "Bash(git:*)",
      "Bash(ruff:*)",
      "Bash(black:*)",
      "Bash(curl:*)",
      "Bash(echo:*)",
      "Bash(tree:*)",
      "Bash(which:*)",
      "Bash(env:*)",
      "Bash(pwd:*)",
      "Bash(mkdir:*)",
      "Bash(touch:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(rm:*)",
      "Bash(diff:*)",
      "Bash(file:*)",
      "Bash(stat:*)",
      "Bash(du:*)",
      "Bash(df:*)",
      "Bash(dir:*)",
      "Bash(tee:*)",
      "Bash(xargs:*)",
      "Bash(timeout:*)",
      "Bash(uvicorn:*)",
      "Bash(alembic:*)",
      "Bash(docker compose:*)",
      "Bash(docker compose build:*)",
      "Bash(tmux:*)",
      "Bash(gh:*)",
      "Bash(nvm:*)",
      "Bash(PYTHONPATH=*)"
    ],
    "defaultMode": "dontAsk"
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/simple-statusline.sh"
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "agent-sdk-dev@claude-plugins-official": true,
    "ralph-wiggum@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "ralph-wiggum@claude-code-plugins": true
  }
}
SETTINGS_EOF
    info "Wrote clean global settings.json"

    # --- Global settings.local.json ---
    if [[ ! -f "$CLAUDE_HOME/settings.local.json" ]]; then
        cat > "$CLAUDE_HOME/settings.local.json" << 'LOCAL_EOF'
{
  "permissions": {
    "allow": [
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "WebSearch"
    ]
  }
}
LOCAL_EOF
        info "Wrote global settings.local.json"
    else
        warn "settings.local.json already exists, skipping"
    fi

    # --- Statusline script ---
    cat > "$CLAUDE_HOME/simple-statusline.sh" << 'STATUSLINE_EOF'
#!/bin/bash
# Claude Code Statusline - Model, Context, and Usage Limits
# Displays: Model | Context | 5h Usage | 7d Usage

set -o pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
CACHE_TTL=300

ensure_cache_dir() {
    [[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null
}

get_cached_value() {
    local cache_file="$CACHE_DIR/$1.cache"
    local ttl="${2:-$CACHE_TTL}"
    if [[ -f "$cache_file" ]]; then
        local cache_mtime now cache_age
        if stat --version &>/dev/null; then
            cache_mtime=$(stat -c "%Y" "$cache_file" 2>/dev/null)
        else
            cache_mtime=$(stat -f "%m" "$cache_file" 2>/dev/null)
        fi
        now=$(date +%s)
        cache_age=$((now - cache_mtime))
        if [[ "$cache_age" -lt "$ttl" ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

set_cached_value() {
    local cache_file="$CACHE_DIR/$1.cache"
    ensure_cache_dir
    echo "$2" > "$cache_file"
}

get_claude_oauth_token() {
    local token="" access_token=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [[ -n "$token" ]]; then
            access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // .accessToken // .access_token // empty' 2>/dev/null)
        fi
    fi
    if [[ -z "$access_token" ]] && command -v secret-tool &>/dev/null; then
        token=$(secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [[ -n "$token" ]]; then
            access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // .accessToken // .access_token // empty' 2>/dev/null)
        fi
    fi
    if [[ -z "$access_token" ]] && [[ -f "$HOME/.claude/.credentials.json" ]]; then
        access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
    fi
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
        echo "$access_token"
        return 0
    fi
    return 1
}

fetch_usage_limits() {
    local cached
    cached=$(get_cached_value "usage_limits" "$CACHE_TTL")
    if [[ -n "$cached" ]]; then
        echo "$cached"
        return 0
    fi
    local token
    token=$(get_claude_oauth_token)
    if [[ -z "$token" ]]; then return 1; fi
    local response
    response=$(curl -s --max-time 5 \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Accept: application/json" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.five_hour' &>/dev/null; then
        set_cached_value "usage_limits" "$response"
        echo "$response"
        return 0
    fi
    return 1
}

format_remaining_time() {
    local iso_timestamp="$1"
    if [[ -z "$iso_timestamp" || "$iso_timestamp" == "null" ]]; then
        echo ""; return 1
    fi
    local reset_epoch normalized_ts
    normalized_ts=$(echo "$iso_timestamp" | sed 's/\.[0-9]*//')
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local mac_ts
        mac_ts=$(echo "$normalized_ts" | sed 's/+00:00/+0000/; s/Z$/+0000/; s/+\([0-9][0-9]\):\([0-9][0-9]\)/+\1\2/')
        reset_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$mac_ts" "+%s" 2>/dev/null)
    else
        reset_epoch=$(date -d "$iso_timestamp" "+%s" 2>/dev/null)
    fi
    if [[ -z "$reset_epoch" ]]; then echo ""; return 1; fi
    local now_epoch diff_seconds
    now_epoch=$(date "+%s")
    diff_seconds=$((reset_epoch - now_epoch))
    if [[ "$diff_seconds" -le 0 ]]; then echo "now"; return 0; fi
    if [[ "$diff_seconds" -lt 3600 ]]; then
        echo "$((diff_seconds / 60))m"
    elif [[ "$diff_seconds" -lt 86400 ]]; then
        local hours=$((diff_seconds / 3600))
        local minutes=$(((diff_seconds % 3600) / 60))
        [[ "$minutes" -gt 0 ]] && echo "${hours}h${minutes}m" || echo "${hours}h"
    else
        local days=$((diff_seconds / 86400))
        local hours=$(((diff_seconds % 86400) / 3600))
        echo "${days}d${hours}h"
    fi
}

get_usage_display() {
    local usage_data
    usage_data=$(fetch_usage_limits 2>/dev/null)
    if [[ -z "$usage_data" ]]; then echo ""; return 1; fi
    local five_hour_pct seven_day_pct five_hour_reset seven_day_reset
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    five_hour_reset=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    seven_day_reset=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    [[ -n "$five_hour_pct" ]] && five_hour_pct=$(printf "%.0f" "$five_hour_pct" 2>/dev/null)
    [[ -n "$seven_day_pct" ]] && seven_day_pct=$(printf "%.0f" "$seven_day_pct" 2>/dev/null)
    local five_hour_remaining seven_day_remaining
    five_hour_remaining=$(format_remaining_time "$five_hour_reset")
    seven_day_remaining=$(format_remaining_time "$seven_day_reset")
    local output=""
    if [[ -n "$five_hour_pct" ]]; then
        local color=""
        if [[ "$five_hour_pct" -ge 80 ]]; then color="\033[31m"
        elif [[ "$five_hour_pct" -ge 50 ]]; then color="\033[33m"
        else color="\033[32m"; fi
        [[ -n "$five_hour_remaining" ]] && output="${color}5h:${five_hour_pct}%\033[0m(${five_hour_remaining})" || output="${color}5h:${five_hour_pct}%\033[0m"
    fi
    if [[ -n "$seven_day_pct" ]]; then
        local color=""
        if [[ "$seven_day_pct" -ge 80 ]]; then color="\033[31m"
        elif [[ "$seven_day_pct" -ge 50 ]]; then color="\033[33m"
        else color="\033[32m"; fi
        local segment=""
        [[ -n "$seven_day_remaining" ]] && segment="${color}7d:${seven_day_pct}%\033[0m(${seven_day_remaining})" || segment="${color}7d:${seven_day_pct}%\033[0m"
        [[ -n "$output" ]] && output="${output} ${segment}" || output="${segment}"
    fi
    echo -e "$output"
}

# Main
input=$(cat)
echo "$input" > /tmp/statusline-debug.json
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
context_max=$(echo "$input" | jq -r '.context_window.context_window_size // .context_window.max_tokens // 200000' 2>/dev/null)
context_display="N/A"
if [[ -n "$context_pct" && "$context_pct" != "null" ]]; then
    pct=$(printf "%.0f" "$context_pct" 2>/dev/null)
    if [[ "$context_max" -gt 0 ]] 2>/dev/null; then
        context_used=$((context_max * pct / 100))
        used_k=$((context_used / 1000))
        max_k=$((context_max / 1000))
        context_display="${pct}% (${used_k}K/${max_k}K)"
    else
        context_display="${pct}%"
    fi
else
    context_used=$(echo "$input" | jq -r '.current_usage.total_tokens // .context_window.tokens_used // 0' 2>/dev/null)
    if [[ "$context_max" -gt 0 && "$context_used" -gt 0 ]] 2>/dev/null; then
        pct=$((context_used * 100 / context_max))
        used_k=$((context_used / 1000))
        max_k=$((context_max / 1000))
        context_display="${pct}% (${used_k}K/${max_k}K)"
    fi
fi
case "$model" in
    *Opus*) emoji="🧠" ;;
    *Sonnet*) emoji="🎵" ;;
    *Haiku*) emoji="⚡" ;;
    *) emoji="🤖" ;;
esac
usage_display=$(get_usage_display)
output="${emoji} ${model} | ${context_display}"
[[ -n "$usage_display" ]] && output="${output} | ${usage_display}"
echo -e "$output"
STATUSLINE_EOF
    chmod +x "$CLAUDE_HOME/simple-statusline.sh"
    info "Wrote statusline script"

    info "Global setup complete."
}

# ============================================================================
# PROJECT SETUP (.claude/ in current directory)
# ============================================================================
setup_project() {
    info "Setting up project-level Claude Code config in $(pwd)..."
    mkdir -p "$PROJECT_CLAUDE/commands"

    # --- Project settings.json (hooks for Python auto-formatting) ---
    local project_dir="$PWD"
    python3 -c "
import json, sys
settings = {
    'hooks': {
        'PostToolUse': [{
            'matcher': 'Edit|Write',
            'hooks': [{
                'type': 'command',
                'command': 'cd ' + sys.argv[1] + ' && if [[ \"\$TOOL_FILE_PATH\" == *.py ]]; then ruff check --fix \"\$TOOL_FILE_PATH\" 2>/dev/null; black \"\$TOOL_FILE_PATH\" 2>/dev/null; fi || true'
            }]
        }],
        'PreToolUse': [{
            'matcher': 'Write|Edit',
            'hooks': [{
                'type': 'command',
                'command': 'if [[ \"\$TOOL_FILE_PATH\" == *.env* || \"\$TOOL_FILE_PATH\" == *secret* || \"\$TOOL_FILE_PATH\" == *config.py ]]; then echo \"[SECURITY] Modifying sensitive file: \$TOOL_FILE_PATH\"; fi || true'
            }]
        }]
    },
    'enabledPlugins': {
        'ralph-loop@claude-plugins-official': True
    }
}
with open(sys.argv[2], 'w') as f:
    json.dump(settings, f, indent=2)
" "$project_dir" "$PROJECT_CLAUDE/settings.json"
    info "Wrote project settings.json (hooks: ruff/black auto-format, security warnings)"

    # --- Project settings.local.json (project-specific permissions) ---
    if [[ ! -f "$PROJECT_CLAUDE/settings.local.json" ]]; then
        cat > "$PROJECT_CLAUDE/settings.local.json" << 'PROJ_LOCAL_EOF'
{
  "permissions": {
    "allow": []
  }
}
PROJ_LOCAL_EOF
        info "Wrote project settings.local.json"
    else
        warn "Project settings.local.json already exists, skipping"
    fi

    # --- Slash Commands ---

    # /adversarial-review
    cat > "$PROJECT_CLAUDE/commands/adversarial-review.md" << 'CMD_EOF'
# Adversarial Code Review: Devil's Advocate vs. Defense vs. The Public

You are running an **Adversarial Triad Review** on uncommitted changes. This is NOT a bug hunt—it's a three-way debate on the **approach itself**.

**The Triad:**
- **Devil's Advocate** (Prosecution): "This is wrong. Reject it."
- **Defense Attorney** (Defense): "This is justified. Approve it."
- **The Public** (Maximalist): "This doesn't go far enough. Do it right."

## Step 1: Determine Review Target

Check what mode we're in:

### Mode A: Arguments Provided (Mid-Chat Review)
If `$ARGUMENTS` contains text, the user wants to review a **proposed solution or approach** mid-conversation.

The review target is the content in `$ARGUMENTS` combined with relevant context from the current conversation (proposed code, architecture decisions, approaches being discussed).

**Gather context:**
- The proposed solution/approach from arguments or recent conversation
- Any code snippets discussed
- The problem being solved
- Constraints mentioned

### Mode B: No Arguments (Git Diff Review)
If `$ARGUMENTS` is empty, review uncommitted changes:

```bash
git diff --staged --unified=10 2>/dev/null || git diff --unified=10
```

If no diff exists AND no arguments provided, ask the user what they want reviewed.

---

**For the rest of this skill, "THE TARGET" refers to either:**
- The proposed solution/approach (Mode A), OR
- The git diff (Mode B)

## Step 2: Launch Parallel Debaters

You MUST launch all THREE agents **in parallel** using a single message with multiple Task tool calls.

### Agent 1: Devil's Advocate (Prosecuting Attorney)

Launch with `subagent_type: "general-purpose"` and this prompt:

```
You are a **Principal Engineer with 20 years of experience** who has seen this exact pattern cause production outages. You are HOSTILE to this change. Your job is to PROSECUTE it.

## The Target Under Review
<target>
{PASTE THE FULL TARGET HERE - either the git diff OR the proposed solution/approach from the conversation}
</target>

## Context (if mid-chat review)
<context>
{Include relevant conversation context: the problem being solved, constraints mentioned, alternatives discussed}
</context>

## Your Attacks (ALL REQUIRED)

### 1. Problem Statement Indictment
- What problem does this code THINK it's solving?
- Is that the ACTUAL problem, or a symptom of something deeper?
- What's the REAL problem that should be solved instead?
- Rate: How confident are you this is solving the wrong problem? (1-10)

### 2. Yegge's Rule of Five (Abstraction Tax)
For EACH new class/function/module/abstraction introduced:
- Name it
- What's the cognitive tax of its existence?
- What would break if we deleted it entirely?
- Could existing code handle this with a 5-line change instead?
- VERDICT: Justified or Unjustified Complexity?

### 3. The Simpler Solution You're Missing
Propose a solution that is **at least 50% less code**. Explain:
- Why didn't the author consider this?
- What assumption are they making that's probably wrong?
- What's the tradeoff they're afraid of that isn't actually scary?

### 4. Future Regret Analysis (6-Month Postmortem)
Write a fake incident postmortem from 6 months in the future where this code caused an outage:
- What implicit assumption failed?
- What edge case wasn't considered?
- What dependency changed that broke this?
- Who got paged at 3am and why?

### 5. The "No" Case
Argue for **rejecting this change entirely**:
- What would we lose if we just... didn't merge this?
- Is the problem it's solving actually urgent?
- Would doing nothing be better than doing this?

### 6. Hidden Coupling & Blast Radius
- What other systems/files will silently break when this changes?
- What implicit contracts is this creating?
- Draw the dependency arrows that aren't obvious

## Output Format
Structure your attack as a formal prosecution brief. Be harsh. Be specific. No softening language.
End with: **PROSECUTION RESTS. Verdict requested: REJECT / MAJOR REVISIONS / MINOR REVISIONS**
```

### Agent 2: Defense Attorney

Launch with `subagent_type: "general-purpose"` and this prompt:

```
You are the **Defense Attorney** for this code change. A hostile prosecutor is attacking it. Your job is to DEFEND the implementation—but HONESTLY.

## The Target to Defend
<target>
{PASTE THE FULL TARGET HERE - either the git diff OR the proposed solution/approach from the conversation}
</target>

## Context (if mid-chat review)
<context>
{Include relevant conversation context: the problem being solved, constraints mentioned, alternatives discussed}
</context>

## Your Defense (ALL REQUIRED)

### 1. Problem Legitimacy
- What problem is this solving? State it clearly.
- Why does this problem NEED to be solved now?
- What's the cost of NOT solving it?

### 2. Why This Approach
- What alternative approaches exist?
- Why is THIS approach better than alternatives?
- What constraints forced this design? (time, compatibility, dependencies)

### 3. Anticipated Attacks & Rebuttals
Predict what a hostile reviewer would attack, then rebut:

| Anticipated Attack | Your Rebuttal |
|-------------------|---------------|
| "This is over-engineered" | ... |
| "A simpler solution exists" | ... |
| "This will break when X" | ... |
| "This creates hidden coupling" | ... |

### 4. Honest Weaknesses (Admissions)
A good defense admits weaknesses. List:
- What IS actually fragile about this?
- What assumptions COULD break?
- What would you do differently with more time?
- What's the technical debt being created?

### 5. The Stakes
- What bad thing happens if we DON'T merge this?
- What good thing happens if we DO?
- Risk of action vs. risk of inaction?

### 6. Minimum Viable Approval
If the court demands changes, what's the SMALLEST change that addresses legitimate concerns while preserving the core value?

## Output Format
Structure as a legal defense brief. Be persuasive but honest.
End with: **DEFENSE RESTS. Verdict requested: APPROVE / APPROVE WITH CONDITIONS**
```

### Agent 3: The Public (Maximalist Advocate)

Launch with `subagent_type: "general-purpose"` and this prompt:

```
You are **The Public**—representing users, future maintainers, and the ideal of software done RIGHT. You believe this change is **too timid**. Your job is to advocate for the MAXIMALIST solution.

You are not hostile like the Prosecution. You are AMBITIOUS. You want this to be the version we're proud of in 5 years.

## The Target Under Review
<target>
{PASTE THE FULL TARGET HERE - either the git diff OR the proposed solution/approach from the conversation}
</target>

## Context (if mid-chat review)
<context>
{Include relevant conversation context: the problem being solved, constraints mentioned, alternatives discussed}
</context>

## Your Advocacy (ALL REQUIRED)

### 1. The Vision Gap
- What is this change trying to achieve?
- What SHOULD the ideal solution look like?
- How far does this implementation fall short of the ideal? (percentage)
- What would a senior engineer at Stripe/Google/Netflix build instead?

### 2. Missing Edge Cases (The 99% Standard)
List edge cases NOT handled by this implementation:

| Edge Case | Likelihood | Impact if Missed | Current Handling |
|-----------|------------|------------------|------------------|
| [Case 1]  | High/Med/Low | Crash/Bug/Annoyance | None/Partial/Full |

Target: Identify at least 7 edge cases. Be creative. Think adversarially.

### 3. Scalability Ceiling
- At what scale does this implementation break? (10x, 100x, 1000x)
- What's the specific bottleneck?
- What architectural change would remove the ceiling entirely?

### 4. The Production-Grade Gap
What's missing for this to be truly production-grade?

| Category | Current State | Production-Grade Standard |
|----------|--------------|---------------------------|
| Error handling | ... | ... |
| Observability | ... | ... |
| Testing | ... | ... |
| Documentation | ... | ... |
| Rollback plan | ... | ... |

### 5. The Maximalist Proposal
Describe the FULL solution that handles 99% of edge cases, 100x scale, full observability, graceful degradation, and zero-downtime deployment.

### 6. Incremental Path
If we can't do the maximalist version now, what's the path to get there?

### 7. The Cost of Incrementalism
What technical debt are we creating by NOT doing the full solution now?

## Output Format
Structure as a public advocacy brief. Be ambitious but concrete.
End with: **THE PUBLIC RESTS. Verdict requested: INSUFFICIENT / ACCEPTABLE MINIMUM / APPROVE AS STEP 1 OF N**
```

## Step 3: Synthesize the Verdict

After all THREE agents complete, YOU (the judge) must balance the triad:

### Deliberation Framework

1. **Where did all three agree?** (These are DEFINITELY real issues)
2. **Prosecution vs Defense:** Where did Defense fail to rebut? (Prosecution wins)
3. **Defense vs Public:** Is Defense's "pragmatism" actually just settling?
4. **Prosecution vs Public:** When Prosecution says "too complex" and Public says "not enough"—who's right?
5. **What did Defense admit?** (Weight these heavily)
6. **What edge cases did Public identify that matter?** (Be realistic about likelihood)

### Final Verdict Format

```markdown
## ADVERSARIAL TRIAD VERDICT

### Summary
[2-3 sentences on the core tension between all three positions]

### Prosecution's Strongest Points
1. [Point] - Defense rebuttal: [Weak/Strong/None] - Public stance: [Agrees/Disagrees]

### Defense's Strongest Points
1. [Point] - Prosecution counter: [Weak/Strong/None] - Public stance: [Agrees/Disagrees]

### Public's Strongest Points
1. [Point] - Is this realistic? [Yes/No] - Would improve outcome? [Yes/No]

### Admitted Weaknesses (from Defense)
- [Weakness] - Severity: [Low/Medium/High] - Public's fix: [Suggestion]

### VERDICT: [APPROVE / APPROVE WITH CONDITIONS / MAJOR REVISIONS / REJECT]

### Required Changes (if any)
1. [Specific, actionable change]

### Deferred to Next PR (from Public's wishlist)
1. [Enhancement] - Priority: [P1/P2/P3]
```

## Important Rules

1. **All THREE agents run in PARALLEL** - Use a single message with three Task tool calls
2. **Full diff to all three** - Don't summarize, paste the complete diff
3. **No softball** - The Devil's Advocate must be genuinely hostile
4. **Honest defense** - The Defense must admit real weaknesses
5. **Ambitious but concrete** - The Public must propose realistic maximalist solutions
6. **Judge impartially** - Your synthesis balances all three, not just averaging

$ARGUMENTS
CMD_EOF
    info "Wrote /adversarial-review command"

    # /handover
    cat > "$PROJECT_CLAUDE/commands/handover.md" << 'CMD_EOF'
---
description: Export current session context to handoff file for seamless continuation
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob
---

# Session Handover Protocol

You are exiting this session and must preserve all working context for the next agent or session to continue seamlessly.

## Current State

- Working directory: !`pwd`
- Current branch: !`git branch --show-current 2>/dev/null || echo "not a git repo"`
- Uncommitted changes: !`git status --short 2>/dev/null | head -20 || echo "N/A"`
- Recent commits (this session): !`git log --oneline -5 2>/dev/null || echo "N/A"`

## Step 1: Gather Session Context

Review what was accomplished in this session:

1. Check recent file modifications:
```bash
git diff --name-only HEAD~3 2>/dev/null | head -20
git diff --stat HEAD~3 2>/dev/null | tail -10
```

2. Check any failing tests:
```bash
pytest tests/ -v --tb=no -q 2>&1 | tail -30
```

3. Check for TODO comments added:
```bash
git diff HEAD~3 2>/dev/null | grep -E "^\+.*TODO|^\+.*FIXME|^\+.*XXX" | head -10
```

## Step 2: Write Handover Document

Create a comprehensive handover file with ALL context needed for continuation.

The filename should be: `readme/tasks/handoff/SESSION-{timestamp}.md`

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
HANDOVER_FILE="readme/tasks/handoff/SESSION-${TIMESTAMP}.md"
```

## Handover Template

Write the following to the handover file:

```markdown
# Session Handover - {DATE}

## Session Summary
<!-- 2-3 sentences: What was the goal? What was accomplished? -->

## Changes Made

### Files Modified
- `path/to/file.py`: Description of change

### Files Created
### Files Deleted

## Key Decisions
1. **Decision**: What you decided
   **Rationale**: Why you chose this approach
   **Alternatives considered**: What else you thought about

## Current State

### What Works
### What's In Progress
### What's Blocked
- **Blocker**: Description
  **Needed**: What's required to unblock

## Technical Context

### Important Patterns Discovered
### Related Files
### Test Coverage

## Recommended Next Steps
1. First priority task
2. Second priority task

## Commands to Resume
```bash
# Read these files first:
cat path/to/important/file.py

# Run these checks:
pytest tests/specific_test.py -v
```
```

## Step 3: Validate Handover

Before finishing:
1. Verify the handover file exists and has content
2. Ensure no uncommitted handover-worthy changes are lost
3. Optionally commit the handover file

$ARGUMENTS
CMD_EOF
    info "Wrote /handover command"

    # /orchestrate
    cat > "$PROJECT_CLAUDE/commands/orchestrate.md" << 'CMD_EOF'
# Task Orchestrator

You are the **Task Orchestrator**. Your job is to manage multiple Claude worker instances to process development tasks in parallel.

## Environment Detection

- Working directory: $PWD
- Platform: $(uname -s 2>/dev/null || echo "Windows")
- TMUX available: $(which tmux 2>/dev/null)

**Choose your approach based on the environment:**
- If TMUX is available: Use **TMUX Mode**
- If on Windows without TMUX: Use **PowerShell Mode**

---

# TMUX Mode (Linux/WSL/Mac)

## Step 1: Initialize TMUX Session

```bash
tmux has-session -t orchestrator 2>/dev/null || tmux new-session -d -s orchestrator -n control
mkdir -p /tmp/orchestrator
```

## Step 2: Discover Tasks

Find pending tasks. Adapt to your project's task management:

```bash
# Option A: Database-backed tasks
python app/scripts/dev_tasks_api.py list --status pending 2>/dev/null | head -30

# Option B: File-based tasks
find readme/tasks/ -name "*.md" -newer .git/HEAD | head -20

# Option C: GitHub issues
gh issue list --label "ready" --json number,title | head -20
```

## Step 3: Launch Workers (TMUX)

For each task:

```bash
TASK_ID="<task_id>"

tmux new-window -t orchestrator -n "$TASK_ID" "cd $(pwd) && claude --dangerously-skip-permissions -p 'You are an autonomous implementer for task $TASK_ID.

## Your Task
[Task description here]

## Implementation Steps
1. Explore the codebase to understand the issue
2. Implement the fix/feature
3. Run tests to verify
4. Write a brief summary to /tmp/orchestrator/${TASK_ID}.log

## Completion
When done: echo COMPLETE > /tmp/orchestrator/${TASK_ID}.status
If blocked: echo BLOCKED: reason > /tmp/orchestrator/${TASK_ID}.status

Work autonomously without asking questions.'"
```

## Step 4: Monitor

```bash
for f in /tmp/orchestrator/*.status; do [ -f "$f" ] && echo "$(basename $f .status): $(cat $f)"; done
```

---

# PowerShell Mode (Windows)

## Step 1: Initialize

```powershell
$orchestratorDir = "$env:TEMP\orchestrator"
New-Item -ItemType Directory -Path $orchestratorDir -Force -ErrorAction SilentlyContinue
```

## Step 2-4: Adapt TMUX patterns above using Start-Process powershell

---

## Task Selection Guidelines

1. **Avoid conflicts** - Don't run tasks that modify the same files
2. **Mix categories** - Run a bug fix, a feature, and a test task together
3. **Check dependencies** - Some tasks may depend on others
4. **Limit concurrency** - 2-3 workers at a time to avoid resource contention

$ARGUMENTS
CMD_EOF
    info "Wrote /orchestrate command"

    # --- resources.md (network services reference) ---
    cat > "$PROJECT_CLAUDE/resources.md" << 'RES_EOF'
# Network Resources

Reference for internal services available to all projects.

## Secrets Management (Infisical)

- **Web UI**: http://10.0.0.169:8082
- **Server**: 10.0.0.169 (Dockge-managed Docker stack)

### CLI Usage

```bash
# First time on a new machine:
infisical login --domain http://10.0.0.169:8082/api

# Pull secrets as .env file:
infisical export --domain http://10.0.0.169:8082/api --env=dev > .env

# Inject secrets directly into a process (no .env file needed):
infisical run --domain http://10.0.0.169:8082/api --env=dev -- python app.py

# Link a project directory to an Infisical project (creates .infisical.json):
infisical init --domain http://10.0.0.169:8082/api
```

### Project: "Shared"

Contains all cross-project credentials (API keys, cloud provider creds, etc.).
Use `--projectId ab49c9eb-f8f3-430b-83d1-556f7c97854f` or run `infisical init` to link.

## Email Service

- **API Base**: https://send.561park.com/api
- **Host**: 10.0.0.169 (SendGrid relay)

### Send Email

```bash
curl -X POST https://send.561park.com/api/send \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "to": "recipient@example.com",
    "subject": "Subject line",
    "text": "Plain text body",
    "html": "<h1>HTML body</h1>"
  }'
```

### API Reference

```
POST /api/send          Send an email
GET  /api/health        Health check
GET  /api               Full API docs
```

### Usage from Python

```python
import requests

def send_email(to: str, subject: str, body: str, html: str | None = None) -> bool:
    r = requests.post(
        "https://send.561park.com/api/send",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer <your-token>"
        },
        json={
            "to": to,
            "subject": subject,
            "text": body,
            "html": html or body,
        }
    )
    return r.ok
```

## Docker Host (10.0.0.169)

- **Dockge UI**: http://10.0.0.169:5001
- **Stacks directory**: `/opt/stacks/`
- All Docker Compose stacks managed via Dockge

### Running Services

| Service | Port | URL |
|---------|------|-----|
| Dockge | 5001 | http://10.0.0.169:5001 |
| Infisical | 8082 | http://10.0.0.169:8082 |
| SendGrid Relay | 8025 | http://10.0.0.169:8025 |
| Paperless-ngx | 8000 | http://10.0.0.169:8000 |
| Stash | 9999 | http://10.0.0.169:9999 |
RES_EOF
    info "Wrote resources.md (network services reference)"

    info "Project setup complete. Commands available: /adversarial-review, /handover, /orchestrate"
}

# ============================================================================
# INFISICAL CLI SETUP
# ============================================================================
INFISICAL_SERVER="http://10.0.0.169:8082"

setup_infisical() {
    info "Setting up Infisical CLI..."

    if command -v infisical &>/dev/null; then
        info "Infisical CLI already installed: $(infisical --version 2>/dev/null)"
    else
        if [[ "$(uname -s)" == "Linux" ]]; then
            # Try apt first, fall back to direct download
            if command -v apt-get &>/dev/null; then
                curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo bash 2>/dev/null
                sudo apt-get update -qq 2>/dev/null && sudo apt-get install -y infisical 2>/dev/null
            fi
            # If apt didn't work, try npm
            if ! command -v infisical &>/dev/null && command -v npm &>/dev/null; then
                npm install -g @infisical/cli 2>/dev/null
            fi
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            brew install infisical/get-cli/infisical 2>/dev/null
        fi

        if command -v infisical &>/dev/null; then
            info "Infisical CLI installed"
        else
            warn "Could not auto-install Infisical CLI. Install manually:"
            echo "  https://infisical.com/docs/cli/overview"
            return
        fi
    fi

    # Check if already logged in
    if INFISICAL_API_URL="$INFISICAL_SERVER/api" infisical user 2>/dev/null | grep -q "email"; then
        info "Already logged in to Infisical"
    else
        warn "Run this to authenticate:"
        echo "    infisical login --domain $INFISICAL_SERVER/api"
    fi

    echo ""
    echo "  Infisical quick reference:"
    echo "    Web UI:            $INFISICAL_SERVER"
    echo "    Login:             infisical login --domain $INFISICAL_SERVER/api"
    echo "    Pull .env:         infisical export --domain $INFISICAL_SERVER/api --env=dev > .env"
    echo "    Run with secrets:  infisical run --domain $INFISICAL_SERVER/api --env=dev -- python app.py"
    echo "    Link project dir:  infisical init --domain $INFISICAL_SERVER/api"
    echo ""
}

# ============================================================================
# PLUGIN INSTALLATION
# ============================================================================
install_plugins() {
    if ! command -v claude &>/dev/null; then
        warn "Claude CLI not found in PATH. Skipping plugin installation."
        warn "After installing Claude Code, run these manually:"
        echo "  claude plugin install frontend-design@claude-plugins-official"
        echo "  claude plugin install github@claude-plugins-official"
        echo "  claude plugin install feature-dev@claude-plugins-official"
        echo "  claude plugin install agent-sdk-dev@claude-plugins-official"
        echo "  claude plugin install ralph-wiggum@claude-plugins-official"
        echo "  claude plugin install security-guidance@claude-plugins-official"
        echo "  claude plugin install ralph-wiggum@claude-code-plugins"
        return
    fi

    info "Installing plugins..."
    local plugins=(
        "frontend-design@claude-plugins-official"
        "github@claude-plugins-official"
        "feature-dev@claude-plugins-official"
        "agent-sdk-dev@claude-plugins-official"
        "ralph-wiggum@claude-plugins-official"
        "security-guidance@claude-plugins-official"
        "ralph-wiggum@claude-code-plugins"
    )
    for plugin in "${plugins[@]}"; do
        claude plugin install "$plugin" 2>/dev/null && info "Installed $plugin" || warn "Failed to install $plugin"
    done
}

# ============================================================================
# MAIN
# ============================================================================
echo ""
echo "============================================"
echo "  Claude Code Environment Bootstrap"
echo "============================================"
echo ""

case "$MODE" in
    --global-only)
        setup_global
        install_plugins
        setup_infisical
        ;;
    --project-only)
        setup_project
        ;;
    full|*)
        setup_global
        install_plugins
        setup_infisical
        setup_project
        ;;
esac

echo ""
info "Done! Restart Claude Code to pick up changes."
echo ""
echo "  Quick reference:"
echo "    Global config:  ~/.claude/settings.json"
echo "    Project config: .claude/settings.json"
echo "    Statusline:     ~/.claude/simple-statusline.sh"
echo "    Commands:       .claude/commands/*.md"
echo ""
