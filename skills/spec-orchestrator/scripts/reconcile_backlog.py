# Copyright Gint Atkinson, gint.atkinson@gmail.com

"""
Backlog reconciliation script that synchronises local markdown spec files
with an external issue tracker (e.g. GitHub Issues).

Scans epics/, features/, user-stories/ and use-cases/ directories,
resolves issue-ID placeholders, updates dependency checklists, syncs
issue bodies, and auto-closes completed items.  Hard-exits on any
referenced issue that does not exist in the tracker (hallucination gate).
"""

#!/usr/bin/env python3
import os
import re
import subprocess
import json
import sys
import yaml
import traceback

def load_codebase_rules(workspace_dir):
    rules_path = os.path.join(workspace_dir, ".pipeline", "logical-ui", "codebase_rules.json")
    if os.path.exists(rules_path):
        try:
            with open(rules_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Failed to load codebase_rules.json: {e}")
    return {}

def get_git_remote_repo(workspace_dir):
    try:
        res = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=workspace_dir,
            capture_output=True,
            text=True,
            check=True
        )
        url = res.stdout.strip()
        if url.endswith(".git"):
            url = url[:-4]
        if "github.com" in url:
            url = re.split(r'github\.com[:/]', url)[-1]
        parts = url.split("/")
        if len(parts) >= 2:
            return f"{parts[-2]}/{parts[-1]}"
    except Exception as e:
        print(f"Warning: Failed to auto-detect git remote: {e}")
    return None

def get_upstream_repository(rules, workspace_dir):
    env_repo = os.environ.get("UPSTREAM_REPOSITORY") or os.environ.get("GIT_REMOTE_ORIGIN")
    if env_repo:
        return env_repo
    git_repo = get_git_remote_repo(workspace_dir)
    if git_repo:
        return git_repo
    return rules.get("meta", {}).get("upstream_repository", "gintatkinson/digital-pipeline-repo")

def format_issue_reference(issue_id, tracker_rules):
    issue_id_str = str(issue_id)
    if issue_id_str.isdigit():
        prefix = tracker_rules.get("numeric_prefix", "#")
        return f"{prefix}{issue_id_str}"
    else:
        prefix = tracker_rules.get("alphanumeric_prefix", "")
        return f"{prefix}{issue_id_str}"

def normalize_title(title, rules=None):
    if not title:
        return ""
    # Strip quotes and leading/trailing whitespace
    title = title.strip().strip('"\'')
    # Strip common prefixes (e.g., epic-01:, feat-02:, us-03:, uc-04:, etc.)
    regex = r'^(epic|feature|feat|user[- ]story|use[- ]case|us|uc)[s]?(?:[- ]*\d+)?\s*[:\-]?\s*'
    title = re.sub(regex, '', title, flags=re.IGNORECASE)
    # Normalize hyphens to spaces to handle typographic variations
    title = title.replace("-", " ")
    # Strip any remaining punctuation and normalize spacing
    title = re.sub(r'[^\w\s]', '', title)
    title = " ".join(title.split())
    return title.lower()

def extract_title(filepath):
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read(2048)  # Read first 2KB
        
        # Try finding title in YAML frontmatter
        title_match = re.search(r'^title:\s*(["\']?)(.*?)\1\s*$', content, re.MULTILINE)
        if title_match:
            return title_match.group(2).strip()
            
        # Fallback to # H1 title
        h1_match = re.search(r'^#\s+(.*?)$', content, re.MULTILINE)
        if h1_match:
            return h1_match.group(1).strip()
    except Exception as e:
        print(f"Error reading title from {filepath}: {e}")
    return None

def get_all_issues(rules=None):
    if not rules:
        raise ValueError("Configuration rules are missing.")
    tracker_rules = rules.get("tracker_rules")
    if not tracker_rules:
        raise ValueError("Missing 'tracker_rules' in codebase_rules.json")
    provider = tracker_rules.get("provider")
    if not provider:
        raise ValueError("Missing 'tracker_rules.provider' in codebase_rules.json")
    commands = tracker_rules.get("commands")
    if not commands or "list_issues" not in commands:
        raise ValueError("Missing 'tracker_rules.commands.list_issues' in codebase_rules.json")
    
    print(f"Fetching active and closed issues from tracker provider '{provider}'...")
    cmd = commands["list_issues"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise Exception(f"Failed to fetch issues: {res.stderr.strip()}")
    return json.loads(res.stdout)

def update_checklist_in_file(filepath, issue_dict, rules=None):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    tracker_rules = rules.get("tracker_rules", {}) if rules else {}
    pattern = tracker_rules.get("dependency_regex", r"(-\s*\[\s*([ xX])\s*\]\s*(#|#\[|\#\s*)?([A-Za-z0-9\-]+))")
    
    updated_content = content
    all_deps_closed = True
    has_deps = False
    
    keys = tracker_rules.get("keys", {})
    state_key = keys.get("state", "state")
    closed_state = keys.get("closed_state_value", "CLOSED").upper()
    
    matches = re.findall(pattern, content)
    for match_tuple in matches:
        # Support variable number of groups depending on user-configured regex
        if isinstance(match_tuple, str):
            full_match = match_tuple
            mark = ' '
            prefix = ''
            dep_num_str = match_tuple
        else:
            full_match = match_tuple[0]
            mark = match_tuple[1]
            prefix = match_tuple[2] if len(match_tuple) > 2 else ''
            dep_num_str = match_tuple[3] if len(match_tuple) > 3 else match_tuple[-1]

        if dep_num_str.isdigit() and not prefix:
            continue
        has_deps = True
        dep_num = int(dep_num_str) if dep_num_str.isdigit() else dep_num_str
        dep_issue = issue_dict.get(dep_num)
        
        if dep_issue is None:
            ref_str = format_issue_reference(dep_num, tracker_rules)
            print(f"Error: Invalid dependency reference {ref_str} in {os.path.basename(filepath)}")
            workspace_root = find_workspace_dir(filepath)
            upstream_repo = get_upstream_repository(rules, workspace_root) if rules else "unknown"
            troubleshooting = rules.get("meta", {}).get("troubleshooting_instruction", "Please report this issue to upstream repository {upstream_repo}") if rules else "Report to {upstream_repo}"
            print(f"\n[!] {troubleshooting.format(upstream_repo=upstream_repo)}")
            sys.exit(1)
            
        is_closed = (str(dep_issue[state_key]).upper() == closed_state)
        target_mark = 'x' if is_closed else ' '
        
        if mark != target_mark:
            # Replace the specific checkbox character
            old_box = f"[{mark}]"
            new_box = f"[{target_mark}]"
            updated_content = updated_content.replace(full_match, full_match.replace(old_box, new_box, 1), 1)
            ref_str = format_issue_reference(dep_num, tracker_rules)
            print(f"  [Checklist] Updated dependency {ref_str} to [{target_mark}] in {os.path.basename(filepath)}")
            
        if not is_closed:
            all_deps_closed = False

    if updated_content != content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(updated_content)
            
    return updated_content, (has_deps and all_deps_closed)

def convert_frontmatter_to_table(content):
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
    if not match:
        return content
    
    frontmatter_text = match.group(1)
    body_text = content[match.end():]
    
    try:
        data = yaml.safe_load(frontmatter_text)
        if not isinstance(data, dict):
            return content
    except Exception as e:
        print(f"Error parsing frontmatter YAML: {e}")
        return content
    
    table_lines = [
        "| Metadata | Value |",
        "| --- | --- |"
    ]
    
    for key, value in data.items():
        if isinstance(value, list):
            val = ", ".join(str(item) for item in value)
        elif value is None:
            val = ""
        else:
            val = str(value)
        table_lines.append(f"| **{key}** | {val} |")
        
    table_text = "\n".join(table_lines) + "\n\n"
    return table_text + body_text

def sync_issue_body_to_tracker(issue_num, filepath, issue_type="Feature", rules=None):
    tracker_rules = rules.get("tracker_rules", {}) if rules else {}
    ref_str = format_issue_reference(issue_num, tracker_rules)
    print(f"  [Sync Issue Body] Syncing {ref_str} ({issue_type}) to tracker...")
    
    temp_path = filepath + ".temp-body"
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
            
        val_rules = rules.get("validation_rules", {}) if rules else {}
        max_body_chars = val_rules.get("max_body_characters", 65536)
        trunc_limit = max_body_chars - 5536
        
        if len(content) > trunc_limit:
            truncation_headers = tracker_rules.get("truncation_headers", ["## Acceptance Criteria", "## User Stories"])
            trunc_index = -1
            for header in truncation_headers:
                trunc_index = content.find(header)
                if trunc_index != -1:
                    break
            if trunc_index == -1:
                trunc_index = trunc_limit
            
            project_root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
            rel_path = os.path.relpath(filepath, project_root)
            
            truncation_template = tracker_rules.get("truncation_message_template", (
                "\n\n---\n*Warning: This issue body has been truncated because it exceeds the tracker size limit of {max_body_chars} characters.*\n"
                "*Please refer to the full specification file in the repository at `{rel_path}` for the complete details.*\n"
            ))
            content = content[:trunc_index] + truncation_template.format(max_body_chars=max_body_chars, rel_path=rel_path)
            
        with open(temp_path, "w", encoding="utf-8") as tf:
            tf.write(content)
        
        edit_cmd_template = tracker_rules.get("commands", {}).get("edit_issue")
        if not edit_cmd_template:
            raise ValueError("Missing 'tracker_rules.commands.edit_issue' in codebase_rules.json")
        cmd = [str(issue_num) if c == "{number}" else (temp_path if c == "{temp_path}" else c) for c in edit_cmd_template]
        subprocess.run(cmd, check=True, capture_output=True)
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
 
def close_issue_on_tracker(issue_num, comment, rules=None):
    tracker_rules = rules.get("tracker_rules", {}) if rules else {}
    ref_str = format_issue_reference(issue_num, tracker_rules)
    print(f"  [Close Issue] Closing issue {ref_str} on tracker...")
    close_cmd_template = tracker_rules.get("commands", {}).get("close_issue")
    if not close_cmd_template:
        raise ValueError("Missing 'tracker_rules.commands.close_issue' in codebase_rules.json")
    cmd = [str(issue_num) if c == "{number}" else (comment if c == "{comment}" else c) for c in close_cmd_template]
    subprocess.run(cmd, check=True, capture_output=True)

def get_current_branch(workspace_dir):
    res = subprocess.run(["git", "branch", "--show-current"], cwd=workspace_dir, capture_output=True, text=True)
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()
    res = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=workspace_dir, capture_output=True, text=True)
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()
    return "master"

def extract_metadata(filepath):
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        match = re.match(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
        if match:
            frontmatter_text = match.group(1)
            data = yaml.safe_load(frontmatter_text)
            if isinstance(data, dict):
                return data
    except Exception as e:
        print(f"Error parsing metadata from {filepath}: {e}")
    return {}

def resolve_type_context(line, filepath, section_context):
    # 1. URL path check
    link_match = re.search(r'\[([^\]]+)\]\(([^)]+)\)', line)
    if link_match:
        path = link_match.group(2)
        if "docs/features" in path or "/features/" in path:
            return "feature"
        elif "docs/user-stories" in path or "/user-stories/" in path:
            return "user-story"
        elif "docs/use-cases" in path or "/use-cases/" in path:
            return "use-case"
        elif "docs/epics" in path or "/epics/" in path:
            return "epic"
            
    # 2. Section context check
    if section_context:
        return section_context
        
    # 3. Line prefix/keywords check
    line_lower = line.lower()
    if "use case" in line_lower or "use-case" in line_lower or "uc-" in line_lower:
        return "use-case"
    if "user story" in line_lower or "user-story" in line_lower or "us-" in line_lower:
        return "user-story"
    if "feature" in line_lower or "feat-" in line_lower:
        return "feature"
    if "epic" in line_lower:
        return "epic"
        
    # 4. File folder context check (default fallback)
    parent_dir = os.path.basename(os.path.dirname(filepath))
    if "features" in parent_dir:
        return "feature"
    elif "user-stories" in parent_dir:
        return "user-story"
    elif "use-cases" in parent_dir:
        return "use-case"
    elif "epics" in parent_dir:
        return "epic"
        
    return None

def resolve_issue_ids_in_file(filepath, epic_titles, feature_titles, story_titles, usecase_titles, rules=None):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        
    tracker_rules = rules.get("tracker_rules", {}) if rules else {}
    placeholder = tracker_rules.get("issue_id_placeholder", "#[IssueID]")
    title_extraction_prefixes_regex = tracker_rules.get("title_extraction_prefixes_regex", r"(?:Feature\s+\d+\s*:\s*|Use\s+Case\s+\d+\s*:\s*|User\s+Story\s+\d+\s*:\s*)?")
    
    if placeholder not in content and "#[EpicIssueID]" not in content:
        return content
        
    lines = content.splitlines()
    updated = False
    
    section_context = None
    for i, line in enumerate(lines):
        # Track section context based on headers
        header_match = re.match(r'^(#+)\s+(.*)$', line)
        if header_match:
            header_text = header_match.group(2).lower()
            if "use case" in header_text:
                section_context = "use-case"
            elif "user story" in header_text or "user-story" in header_text:
                section_context = "user-story"
            elif "feature" in header_text or "requirement" in header_text:
                section_context = "feature"
            elif "epic" in header_text:
                section_context = "epic"
                
        if placeholder not in line and "#[EpicIssueID]" not in line:
            continue
            
        active_placeholder = placeholder if placeholder in line else "#[EpicIssueID]"
        escaped_active = re.escape(active_placeholder)
        
        title = None
        link_label_match = re.search(r'\[([^\]]+)\]\(', line)
        if link_label_match:
            title = link_label_match.group(1).strip()
        else:
            pattern = escaped_active + r'(?:\s*[-:]\s*)?' + title_extraction_prefixes_regex + r'(.*)$'
            dash_match = re.search(pattern, line)
            if dash_match:
                title = dash_match.group(1).strip()
                title = re.sub(r'\(.*?\)', '', title).strip()
                title = title.strip('[]-* ')
                
        if title:
            norm = normalize_title(title, rules)
            type_context = resolve_type_context(line, filepath, section_context)
            if active_placeholder == "#[EpicIssueID]":
                type_context = "epic"
            issue_num = None
            if type_context == "epic":
                issue_num = epic_titles.get(norm)
            elif type_context == "feature":
                issue_num = feature_titles.get(norm)
            elif type_context == "user-story":
                issue_num = story_titles.get(norm)
            elif type_context == "use-case":
                issue_num = usecase_titles.get(norm)
                
            if not issue_num:
                issue_num = (feature_titles.get(norm) or 
                             story_titles.get(norm) or 
                             usecase_titles.get(norm) or 
                             epic_titles.get(norm))
                             
            if issue_num:
                ref_str = format_issue_reference(issue_num, tracker_rules)
                lines[i] = line.replace(active_placeholder, ref_str)
                updated = True
                print(f"  [Resolve ID] Resolved {active_placeholder} to {ref_str} for '{title}' (type: {type_context}) in {os.path.basename(filepath)}")
            else:
                print(f"  [Warning] Could not resolve {active_placeholder} for title '{title}' in {os.path.basename(filepath)}")
                
    if updated:
        new_content = "\n".join(lines) + "\n"
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)
        return new_content
        
    return content

def reconcile_epic_checklists(filepath, child_features, child_stories, child_usecases, epic_titles, feature_titles, story_titles, usecase_titles, rules):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines()
    
    idx_req = -1
    idx_usecases = -1
    idx_stories = -1
    idx_next = -1
    
    for idx, line in enumerate(lines):
        line_clean = line.strip()
        if line_clean.startswith("## 2. Requirements & Checklist"):
            idx_req = idx
        elif line_clean.startswith("#### Associated Use Cases"):
            idx_usecases = idx
        elif line_clean.startswith("#### Associated User Stories"):
            idx_stories = idx
        elif idx_req != -1 and line_clean.startswith("## ") and idx > idx_req and not line_clean.startswith("## 2."):
            if idx_next == -1:
                idx_next = idx

    def extract_items_from_range(start_idx, end_idx):
        items = []
        if start_idx == -1:
            return items
        limit = end_idx if end_idx != -1 else len(lines)
        for i in range(start_idx + 1, limit):
            l = lines[i].strip()
            if l.startswith("#"):
                break
            if l.startswith("- [ ]") or l.startswith("- [x]") or l.startswith("- [X]"):
                if "feat-XX-name" in l or "uc-XX-name" in l or "us-XX-name" in l or "Feature 1:" in l or "Use Case 1:" in l or "User Story 1:" in l:
                    continue
                items.append(lines[i])
        return items

    end_req = idx_usecases if idx_usecases != -1 else (idx_stories if idx_stories != -1 else idx_next)
    end_usecases = idx_stories if idx_stories != -1 else idx_next
    end_stories = idx_next
    
    existing_features = extract_items_from_range(idx_req, end_req)
    existing_usecases = extract_items_from_range(idx_usecases, end_usecases)
    existing_stories = extract_items_from_range(idx_stories, end_stories)
    
    indent = ""
    for item in existing_features + existing_usecases + existing_stories:
        m = re.match(r'^(\s*)', item)
        if m and m.group(1):
            indent = m.group(1)
            break

    workspace_root = find_workspace_dir(filepath)
    upstream_repo = get_upstream_repository(rules, workspace_root)
    repo_base = upstream_repo
    if not repo_base.startswith("http"):
        repo_base = f"https://github.com/{repo_base}"
    branch_name = get_current_branch(workspace_root)
    
    def format_item(item_type, filename, title, issue_num):
        tracker_rules = rules.get("tracker_rules", {}) if rules else {}
        ref_str = format_issue_reference(issue_num, tracker_rules) if issue_num else tracker_rules.get("issue_id_placeholder", "#[IssueID]")
        
        if item_type == "feature":
            path_part = f"docs/features/{filename}.md"
        elif item_type == "use-case":
            path_part = f"docs/use-cases/{filename}.md"
        else:
            path_part = f"docs/user-stories/{filename}.md"
            
        return f"{indent}- [ ] {ref_str} - [{title}]({repo_base}/blob/{branch_name}/{path_part}) (semantic linkage justification)"

    def get_filename_key(item_str):
        m = re.search(r'docs/(features|use-cases|user-stories)/([a-zA-Z0-9_\-]+)\.md', item_str)
        if m:
            return m.group(2)
        return None

    final_features = []
    seen_feats = set()
    for item in existing_features:
        key = get_filename_key(item)
        if key:
            seen_feats.add(key)
            final_features.append(item)
            
    for fn, title in child_features:
        if fn not in seen_feats:
            issue_num = feature_titles.get(normalize_title(title, rules))
            final_features.append(format_item("feature", fn, title, issue_num))
            seen_feats.add(fn)
            
    final_usecases = []
    seen_ucs = set()
    for item in existing_usecases:
        key = get_filename_key(item)
        if key:
            seen_ucs.add(key)
            final_usecases.append(item)
            
    for fn, title in child_usecases:
        if fn not in seen_ucs:
            issue_num = usecase_titles.get(normalize_title(title, rules))
            final_usecases.append(format_item("use-case", fn, title, issue_num))
            seen_ucs.add(fn)
            
    final_stories = []
    seen_stories = set()
    for item in existing_stories:
        key = get_filename_key(item)
        if key:
            seen_stories.add(key)
            final_stories.append(item)
            
    for fn, title in child_stories:
        if fn not in seen_stories:
            issue_num = story_titles.get(normalize_title(title, rules))
            final_stories.append(format_item("user-story", fn, title, issue_num))
            seen_stories.add(fn)

    new_lines = []
    if idx_req != -1:
        new_lines.extend(lines[:idx_req + 1])
        new_lines.extend(final_features)
        
        if idx_usecases != -1:
            new_lines.extend(lines[idx_req + 1 + len(existing_features) : idx_usecases + 1])
        else:
            new_lines.append("")
            new_lines.append(f"{indent}### Associated Use Cases & User Stories")
            new_lines.append("")
            new_lines.append(f"{indent}#### Associated Use Cases")
            
        new_lines.extend(final_usecases)
        
        if idx_stories != -1:
            new_lines.extend(lines[idx_usecases + 1 + len(existing_usecases) : idx_stories + 1])
        else:
            new_lines.append("")
            new_lines.append(f"{indent}#### Associated User Stories")
            
        new_lines.extend(final_stories)
        
        start_after_stories = idx_stories + 1 + len(existing_stories) if idx_stories != -1 else len(lines)
        if idx_next != -1:
            new_lines.extend(lines[start_after_stories:idx_next])
            new_lines.extend(lines[idx_next:])
        else:
            new_lines.extend(lines[start_after_stories:])
    else:
        return

    new_content = "\n".join(new_lines) + "\n"
    if new_content != content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"  [Reconcile Checklist] Updated checklists in {os.path.basename(filepath)}")

def find_workspace_dir(start_path):
    curr = os.path.abspath(start_path)
    while True:
        if os.path.exists(os.path.join(curr, ".pipeline", "logical-ui", "codebase_rules.json")):
            return curr
        parent = os.path.dirname(curr)
        if parent == curr:
            break
        curr = parent
    return os.path.abspath(start_path)

def main():
    if "GITHUB_TOKEN" in os.environ and "dummytoken" in os.environ["GITHUB_TOKEN"]:
        del os.environ["GITHUB_TOKEN"]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = find_workspace_dir(script_dir)

    try:
        rules_path = os.path.join(workspace_dir, ".pipeline", "logical-ui", "codebase_rules.json")
        if not os.path.exists(rules_path):
            print(f"Error: codebase_rules.json not found at: {rules_path}")
            print("Please ensure the configuration file is present at '.pipeline/logical-ui/codebase_rules.json'.")
            sys.exit(1)

        rules = load_codebase_rules(workspace_dir)
        if not rules:
            print("Error: codebase_rules.json is empty, invalid, or could not be loaded.")
            print("Please check '.pipeline/logical-ui/codebase_rules.json' and ensure it contains valid configuration.")
            sys.exit(1)

        try:
            issues = get_all_issues(rules)
        except Exception as e:
            print(f"Error fetching issues: {e}")
            print("Please ensure issue tracker CLI is authenticated and configured.")
            sys.exit(1)

        tracker_rules = rules.get("tracker_rules", {}) if rules else {}
        keys = tracker_rules.get("keys", {})
        id_key = keys.get("issue_id", "number")
        title_key = keys.get("title", "title")
        labels_key = keys.get("labels", "labels")
        state_key = keys.get("state", "state")
        closed_state = keys.get("closed_state_value", "CLOSED").upper()
        
        close_comments = tracker_rules.get("close_comments", {})
        epic_comment = close_comments.get("epic", "Epic completed. All constituent features successfully delivered and verified.")
        story_comment_template = close_comments.get("user_story", "Resolved. All dependent features/tasks for BDD scenario '{title}' have been completed and verified.")
        usecase_comment_template = close_comments.get("use_case", "Resolved. All dependent user stories and features for use case '{title}' are completed.")

        issue_dict = {}
        for issue in issues:
            raw_id = issue[id_key]
            issue_dict[raw_id] = issue
            if isinstance(raw_id, str) and raw_id.isdigit():
                issue_dict[int(raw_id)] = issue
            elif isinstance(raw_id, int):
                issue_dict[str(raw_id)] = issue

        epic_titles = {}
        story_titles = {}
        usecase_titles = {}
        feature_titles = {}

        labels_config = tracker_rules.get("labels", {})
        epic_label = labels_config.get("epic", "epic").lower()
        story_label = labels_config.get("user_story", "user-story").lower()
        usecase_label = labels_config.get("use_case", "use-case").lower()
        feature_label = labels_config.get("feature", "feature").lower()

        for num, issue in issue_dict.items():
            if isinstance(num, str) and num.isdigit() and int(num) in epic_titles:
                continue
            norm_title = normalize_title(issue[title_key], rules)
            labels = []
            for l in issue.get(labels_key, []):
                if isinstance(l, dict):
                    labels.append(l.get("name", "").lower())
                elif isinstance(l, str):
                    labels.append(l.lower())
            
            if epic_label in labels:
                epic_titles[norm_title] = num
            elif story_label in labels:
                story_titles[norm_title] = num
            elif usecase_label in labels:
                usecase_titles[norm_title] = num
            elif feature_label in labels:
                feature_titles[norm_title] = num
            
        backlog_dirs = rules.get("backlog_directories")
        if not backlog_dirs:
            raise ValueError("Missing 'backlog_directories' in codebase_rules.json")
            
        epics_rel = backlog_dirs.get("epics")
        features_rel = backlog_dirs.get("features")
        stories_rel = backlog_dirs.get("user_stories")
        usecases_rel = backlog_dirs.get("use_cases")
        
        if not all([epics_rel, features_rel, stories_rel, usecases_rel]):
            raise ValueError("Missing epic, features, user_stories, or use_cases path in backlog_directories configuration")
            
        upstream_repo = get_upstream_repository(rules, workspace_dir)
        if not upstream_repo:
            raise ValueError("Missing 'meta.upstream_repository' in codebase_rules.json and remote origin is not configured")

        if len(sys.argv) > 1:
            docs_dir = os.path.abspath(sys.argv[1])
            epics_dir = os.path.join(docs_dir, os.path.basename(epics_rel))
            features_dir = os.path.join(docs_dir, os.path.basename(features_rel))
            stories_dir = os.path.join(docs_dir, os.path.basename(stories_rel))
            usecases_dir = os.path.join(docs_dir, os.path.basename(usecases_rel))
            print(f"Scanning backlog files in {docs_dir}...")
        else:
            epics_dir = os.path.join(workspace_dir, epics_rel)
            features_dir = os.path.join(workspace_dir, features_rel)
            stories_dir = os.path.join(workspace_dir, stories_rel)
            usecases_dir = os.path.join(workspace_dir, usecases_rel)
            print(f"Scanning backlog files...")

        # Dynamic relationship scanning
        feature_to_epic = {}
        if os.path.exists(features_dir):
            for fn in os.listdir(features_dir):
                if fn.endswith(".md"):
                    fp = os.path.join(features_dir, fn)
                    meta = extract_metadata(fp)
                    epic_name = meta.get("epic")
                    if epic_name:
                        epic_norm = normalize_title(epic_name, rules)
                        feature_to_epic[fn[:-3]] = {epic_norm}

        story_to_epic = {}
        if os.path.exists(stories_dir):
            for fn in os.listdir(stories_dir):
                if fn.endswith(".md"):
                    fp = os.path.join(stories_dir, fn)
                    meta = extract_metadata(fp)
                    epic_name = meta.get("epic")
                    epics = set()
                    if epic_name:
                        epics.add(normalize_title(epic_name, rules))
                    
                    with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    feature_refs = re.findall(r'(?:docs/features/|/features/)([a-zA-Z0-9_\-]+)\.md', content)
                    for feat in feature_refs:
                        if feat in feature_to_epic:
                            epics.update(feature_to_epic[feat])
                    
                    story_to_epic[fn[:-3]] = epics

        usecase_to_epic = {}
        if os.path.exists(usecases_dir):
            for fn in os.listdir(usecases_dir):
                if fn.endswith(".md"):
                    fp = os.path.join(usecases_dir, fn)
                    meta = extract_metadata(fp)
                    epic_name = meta.get("epic")
                    epics = set()
                    if epic_name:
                        epics.add(normalize_title(epic_name, rules))
                        
                    with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    feature_refs = re.findall(r'(?:docs/features/|/features/)([a-zA-Z0-9_\-]+)\.md', content)
                    for feat in feature_refs:
                        if feat in feature_to_epic:
                            epics.update(feature_to_epic[feat])
                    story_refs = re.findall(r'(?:docs/user-stories/|/user-stories/)([a-zA-Z0-9_\-]+)\.md', content)
                    for story in story_refs:
                        if story in story_to_epic:
                            epics.update(story_to_epic[story])
                            
                    usecase_to_epic[fn[:-3]] = epics

        # Reconcile Epic checklists
        if os.path.exists(epics_dir):
            for filename in sorted(os.listdir(epics_dir)):
                if not filename.endswith(".md"):
                    continue
                filepath = os.path.join(epics_dir, filename)
                title = extract_title(filepath)
                if not title:
                    continue
                epic_norm = normalize_title(title, rules)
                
                child_features = []
                if os.path.exists(features_dir):
                    for feat_fn in sorted(os.listdir(features_dir)):
                        if feat_fn.endswith(".md"):
                            feat_fp = os.path.join(features_dir, feat_fn)
                            if epic_norm in feature_to_epic.get(feat_fn[:-3], set()):
                                feat_title = extract_title(feat_fp)
                                if feat_title:
                                    child_features.append((feat_fn[:-3], feat_title))

                child_stories = []
                if os.path.exists(stories_dir):
                    for story_fn in sorted(os.listdir(stories_dir)):
                        if story_fn.endswith(".md"):
                            story_fp = os.path.join(stories_dir, story_fn)
                            if epic_norm in story_to_epic.get(story_fn[:-3], set()):
                                story_title = extract_title(story_fp)
                                if story_title:
                                    child_stories.append((story_fn[:-3], story_title))

                child_usecases = []
                if os.path.exists(usecases_dir):
                    for uc_fn in sorted(os.listdir(usecases_dir)):
                        if uc_fn.endswith(".md"):
                            uc_fp = os.path.join(usecases_dir, uc_fn)
                            if epic_norm in usecase_to_epic.get(uc_fn[:-3], set()):
                                uc_title = extract_title(uc_fp)
                                if uc_title:
                                    child_usecases.append((uc_fn[:-3], uc_title))

                reconcile_epic_checklists(
                    filepath, 
                    child_features, 
                    child_stories, 
                    child_usecases, 
                    epic_titles, 
                    feature_titles, 
                    story_titles, 
                    usecase_titles, 
                    rules
                )

        # Process Epics
        if os.path.exists(epics_dir):
            for filename in sorted(os.listdir(epics_dir)):
                if not filename.endswith(".md"):
                    continue
                filepath = os.path.join(epics_dir, filename)
                resolve_issue_ids_in_file(filepath, epic_titles, feature_titles, story_titles, usecase_titles, rules=rules)
                title = extract_title(filepath)
                if not title:
                    continue
                
                norm = normalize_title(title, rules=rules)
                issue_num = epic_titles.get(norm)
                if issue_num:
                    updated_content, completed = update_checklist_in_file(filepath, issue_dict, rules)
                    is_open = str(issue_dict[issue_num][state_key]).upper() == keys.get("open_state_value", "OPEN").upper()
                    if is_open:
                        sync_issue_body_to_tracker(issue_num, filepath, issue_type="Epic", rules=rules)
                        if completed:
                            close_issue_on_tracker(
                                issue_num, 
                                epic_comment,
                                rules=rules
                            )
                            issue_dict[issue_num][state_key] = closed_state
                else:
                    print(f"Warning: No Epic issue found on tracker matching: '{title}'")

        # Process Features
        if os.path.exists(features_dir):
            for filename in sorted(os.listdir(features_dir)):
                if not filename.endswith(".md"):
                    continue
                filepath = os.path.join(features_dir, filename)
                resolve_issue_ids_in_file(filepath, epic_titles, feature_titles, story_titles, usecase_titles, rules=rules)
                title = extract_title(filepath)
                if not title:
                    continue
                
                norm = normalize_title(title, rules=rules)
                issue_num = feature_titles.get(norm)
                if issue_num:
                    is_open = str(issue_dict[issue_num][state_key]).upper() == keys.get("open_state_value", "OPEN").upper()
                    if is_open:
                        sync_issue_body_to_tracker(issue_num, filepath, issue_type="Feature", rules=rules)
                else:
                    print(f"Warning: No Feature issue found on tracker matching: '{title}'")

        # Process User Stories
        if os.path.exists(stories_dir):
            for filename in sorted(os.listdir(stories_dir)):
                if not filename.endswith(".md"):
                    continue
                filepath = os.path.join(stories_dir, filename)
                resolve_issue_ids_in_file(filepath, epic_titles, feature_titles, story_titles, usecase_titles, rules=rules)
                title = extract_title(filepath)
                if not title:
                    continue
                
                norm = normalize_title(title, rules=rules)
                issue_num = story_titles.get(norm)
                if issue_num:
                    _, completed = update_checklist_in_file(filepath, issue_dict, rules)
                    is_open = str(issue_dict[issue_num][state_key]).upper() == keys.get("open_state_value", "OPEN").upper()
                    if is_open:
                        sync_issue_body_to_tracker(issue_num, filepath, issue_type="User Story", rules=rules)
                        if completed:
                            close_issue_on_tracker(
                                issue_num,
                                story_comment_template.format(title=title),
                                rules=rules
                            )
                            issue_dict[issue_num][state_key] = closed_state
                else:
                    print(f"Warning: No User Story issue found on tracker matching: '{title}'")

        # Process Use Cases
        if os.path.exists(usecases_dir):
            for filename in sorted(os.listdir(usecases_dir)):
                if not filename.endswith(".md"):
                    continue
                filepath = os.path.join(usecases_dir, filename)
                resolve_issue_ids_in_file(filepath, epic_titles, feature_titles, story_titles, usecase_titles, rules=rules)
                title = extract_title(filepath)
                if not title:
                    continue
                
                norm = normalize_title(title, rules=rules)
                issue_num = usecase_titles.get(norm)
                if issue_num:
                    _, completed = update_checklist_in_file(filepath, issue_dict, rules)
                    is_open = str(issue_dict[issue_num][state_key]).upper() == keys.get("open_state_value", "OPEN").upper()
                    if is_open:
                        sync_issue_body_to_tracker(issue_num, filepath, issue_type="Use Case", rules=rules)
                        if completed:
                            close_issue_on_tracker(
                                issue_num,
                                usecase_comment_template.format(title=title),
                                rules=rules
                            )
                            issue_dict[issue_num][state_key] = closed_state
                else:
                    print(f"Warning: No Use Case issue found on tracker matching: '{title}'")

        print("Backlog reconciliation complete.")

    except BaseException as e:
        exit_code = 1
        if isinstance(e, SystemExit):
            if isinstance(e.code, int):
                exit_code = e.code
            elif e.code is None:
                exit_code = 0
        
        if exit_code != 0:
            tb_str = traceback.format_exc()
            print(tb_str, file=sys.stderr)
            try:
                # Insert the src directory of the parity_auditor package into sys.path
                src_dir = os.path.abspath(os.path.join(workspace_dir, "skills", "spec-orchestrator", "parity_auditor", "src"))
                if src_dir not in sys.path:
                    sys.path.insert(0, src_dir)
                from parity_auditor.utils.diagnostics import serialize_diagnostics
                serialize_diagnostics(
                    workspace_dir=workspace_dir,
                    tool_name="reconcile_backlog",
                    exit_code=exit_code,
                    errors=[str(e)],
                    traceback_str=tb_str
                )
            except Exception as diag_err:
                print(f"Warning: Failed to serialize diagnostics: {diag_err}", file=sys.stderr)
        raise

if __name__ == "__main__":
    main()
# Refresh commit timestamp
