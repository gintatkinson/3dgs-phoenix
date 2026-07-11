<!-- Copyright 2026. All rights reserved. -->

---
name: debug-protocol
description: "8-step Recursive Debugging Protocol for systematic bug hunting. BUG ISSUES ONLY — do NOT use for features, enhancements, epics, chores, or refactors. Use when fixing defects to follow a rigorous hypothesis-driven loop with dedicated subagents per step."
compatibility: "Works with any agent runtime. Requires GitHub CLI (`gh`) for issue management."
metadata:
  title: "Recursive Debugging Protocol (8-Step Bug Loop)"
  category: debugging
  risk: low
---

> **⚠️ THIS PROTOCOL IS FOR BUGS AND DEFECTS ONLY**
>
> If the task is a feature request, enhancement, epic, chore, refactor, or new functionality — **DO NOT USE THIS PROTOCOL.** Stop immediately and report back.
>
> **Only use this when there is a clear defect:** something is broken, incorrect, or behaving unexpectedly compared to specification.

# Recursive Debugging Protocol

## Step 0 — Verify: Is this a bug?

Before starting, confirm:
- Is there existing behavior that is wrong? (bug)
- Or is this adding new behavior that doesn't exist yet? (feature)

If bug — proceed to Step 0.1.

### Step 0.1 — Pre-flight: Unattended Setup
To prevent the user from being interrupted by endless permission prompts, the executing agent MUST immediately request the following permissions at the start of the task using the `ask_permission` tool:
1. **Command prefixes**: Request permission for the following command prefixes to enable unattended git/gh/flutter operations:
   - `git`
   - `gh`
   - `flutter`
2. **File permissions**: Request write permission for the workspace root to ensure no write permission failures occur during edits:
   - `<absolute_workspace_path>` (or local equivalent)

Once these permissions are requested and approved by the user, proceed to Step 1.

## Step 1 — Reproduction Subagent
Dispatch a subagent to: Gather complete symptom info, reproduce the bug consistently, determine scope (isolated or systemic), and check environment (version, platform). Return reproduction steps and scope report.

## Step 2 — Hypothesis Subagent
Dispatch a subagent to: Generate multiple hypotheses ranked by likelihood. Consider recent changes, data/state issues, race conditions, edge cases, interaction effects. Return a ranked list of hypotheses.

## Step 3 — Investigation Subagent
Dispatch a subagent to: Binary-search the problem space. Add strategic logging at key decision points. Trace data flow from input to output. Verify ALL assumptions — do not assume. Return evidence of what was tried and observed.

## Step 4 — Evidence Subagent
Dispatch a subagent to: Document all evidence, code snippets, logs, error messages, patterns. Track which hypotheses have been ruled out and why. Return a structured evidence dossier.

## Step 5 — Root Cause Subagent
Dispatch a subagent to: Distinguish root cause from symptoms. Apply "5 whys" to drill to the actual cause. Verify the root cause explains ALL observed symptoms. Return root cause with file:line references.

## Step 6 — Fix Subagent
Dispatch a subagent to: Design and implement the minimal fix. Consider side effects. Add regression tests. Document the fix. Stage, commit, and push all changes to the remote repository. Update the GitHub issue with root cause and fix details. Return fix summary and issue URL.

## Step 7 — Verification Subagent
Dispatch a subagent to: Confirm bug is fixed using original reproduction steps. Test edge cases. Verify no regressions (test suite must pass). Once verified, comment on and close the GitHub issue to mark it as resolved. Return pass/fail result.

## Step 8 — Loop Decision
If Step 7 failed, return to Step 1. Do NOT give up after one or two failed hypotheses. If stuck, reconsider assumptions.

If the issue is a meta-issue with multiple independent sub-items (e.g. "eliminate all hardcoded data" with 14 items), treat each sub-item as one pass through Steps 1-7. After Step 7 passes for the current sub-item, return to Step 1 for the next sub-item. Do NOT stop to ask, report, or plan — just loop.

On completion of the current bug, query the repository for the next unresolved bug/defect issue (e.g. using `gh issue list --label "bug"`).
- If other unresolved bugs exist:
  1. Select the next highest priority or oldest bug.
  2. Skip any issues that are already assigned to someone else or explicitly marked as in-progress.
  3. Start a new Step 1-7 debugging loop on that bug.
- If a bug cannot be resolved or reproduced after 3 full hypothesis/fix iterations (Steps 1-7), post a detailed status comment summarizing the reproduction/investigation findings on the issue, skip it, and proceed to the next unresolved bug in the backlog.
- Do NOT stop until there are ZERO unresolved bugs remaining in the repository backlog.

## Persistence Rules
- Each step MUST use a fresh subagent — do not reuse or combine
- Do NOT skip or combine steps
- Document every attempt even if the bug isn't fully solved
- If a subagent fails to complete its step, dispatch another with more specific instructions

## Debugging Checklist
- [ ] Step 0: Confirmed this is a bug (not a feature)
- [ ] Step 1 subagent dispatched and reported
- [ ] Step 2 subagent dispatched and reported
- [ ] Step 3 subagent dispatched and reported
- [ ] Step 4 subagent dispatched and reported
- [ ] Step 5 subagent dispatched and reported
- [ ] Step 6 subagent dispatched, fix applied, changes committed and pushed, issue updated
- [ ] Step 7 subagent dispatched, tests pass, issue closed
- [ ] Loop closed (bug fixed) or loop restarted (bug persists)
