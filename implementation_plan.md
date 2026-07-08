# Implementation Plan - Reconcile Epic Backlog Issues

## 1. Objectives
- Clean up incorrect `issue_id` entries in epic frontmatter to trigger fresh registration on GitHub.
- Run the backlog reconciler script to register new/modified epics.
- Verify changes and push them back to the remote repository.

## 2. File Modifications

### docs/epics/epic-02-scene-lifecycle.md
- **Manual Change**: Remove `issue_id: 244` from frontmatter.
- **Reconciler Change**: The backlog reconciler script will write the correct `issue_id` back to the frontmatter.

### docs/epics/epic-04-wasm-extensibility.md
- **Manual Change**: Remove `issue_id: 247` from frontmatter.
- **Reconciler Change**: The backlog reconciler script will write the correct `issue_id` back to the frontmatter.

### docs/epics/epic-03-gpu-bridge.md
- **Reconciler Change**: The backlog reconciler script will write the correct `issue_id` back to the frontmatter.

## 3. Execution Commands
1. Run: `python3 .agents/skills/spec-orchestrator/scripts/reconcile_backlog.py`
2. Run git command sequence to commit changes and push to `origin/main`.

## 4. Success / Verification Criteria
- `docs/epics/epic-02-scene-lifecycle.md`, `docs/epics/epic-03-gpu-bridge.md`, and `docs/epics/epic-04-wasm-extensibility.md` all contain the correct `issue_id` written back to their frontmatter.
- `git diff origin/main` is empty after push.
