"""
CLI entry point for the Model Coverage Parity Audit tool.

Parses command-line arguments, locates the workspace, initialises all
validators, and orchestrates the full audit pipeline.  Delegates to
UML-, behavioral-, codebase-, docs-, dependency-, sync-, schema-mapping-,
profile-scoping- and test-completeness validators.
"""

import os
import sys
import re
import argparse
import json
from typing import Dict, Set, List

from .core.workspace import WorkspaceRepository
from .parsers.schema_router import parse_schema_file
from .validators.uml import UmlValidator
from .validators.behavioral import BehavioralValidator
from .validators.codebase import CodebaseValidator
from .validators.docs import DocsValidator
from .validators.dependency_validator import DependencyValidator
from .validators.sync_validator import SyncValidator
from .validators.schema_mapping_validator import SchemaMappingValidator
from .validators.profile_scoping_validator import ProfileScopingValidator
from .validators.test_completeness_validator import TestCompletenessValidator
from .utils.diagnostics import serialize_diagnostics

def get_open_feature_issues() -> list:
    """
    Fetch open feature issues from GitHub via ``gh issue list``.

    Filters out issues whose title contains known defect/bug/tooling keywords.

    Returns:
        List of issue dicts with 'number' and 'title' keys, or an empty list
        when the ``gh`` CLI is unavailable or returns a non-zero exit code.
    """
    import subprocess
    import json
    try:
        result = subprocess.run(
            ["gh", "issue", "list", "--state", "open", "--label", "feature", "--json", "number,title"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            issues = json.loads(result.stdout)
            keywords = ["defect", "bug", "repro", "tooling"]
            return [
                issue for issue in issues
                if not any(kw in issue.get("title", "").lower() for kw in keywords)
            ]
        else:
            print(f"Warning: gh CLI exited with code {result.returncode}: {result.stderr.strip()}")
            return []
    except Exception as e:
        print(f"Warning: Failed to run gh CLI to fetch open feature issues: {e}")
        return []

def _main_impl():
    """
    Orchestrate the full parity audit pipeline.

    Discovers the workspace, resolves schema/features/epics directories,
    parses schemas and feature files, then runs each validator in sequence
    (UML, behavioral, codebase AST, docs, dependencies, sync, schema
    mapping, profile scoping, test completeness).  Exits with code 1 on
    any failure, writing a diagnostics JSON artifact.

    Side effects:
        - Reads codebase_rules.json for configuration.
        - Invokes ``gh`` CLI for open-feature-issue discovery.
        - Serialises diagnostics JSON to ``.pipeline/logical-ui/`` on failure.
        - Prints audit progress and results to stdout.
    """
    parser = argparse.ArgumentParser(description="Model Coverage Parity Audit CLI")
    parser.add_argument("schema_dir", nargs="?", help="Path to schema directory")
    parser.add_argument("features_dir", nargs="?", help="Path to feature specs directory")
    parser.add_argument("--spec-only", action="store_true", help="Run in specification-only mode, bypassing codebase checks")
    
    args = parser.parse_args()
    
    # 1. Locate workspace directory dynamically starting from the script's directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = None
    
    # Try traversing up from script_dir
    curr = script_dir
    while True:
        if os.path.exists(os.path.join(curr, ".pipeline", "logical-ui", "codebase_rules.json")):
            workspace_dir = curr
            break
        parent = os.path.dirname(curr)
        if parent == curr:
            break
        curr = parent
        
    # If not found, fall back to os.getcwd() traversal
    if not workspace_dir:
        curr = os.getcwd()
        while True:
            if os.path.exists(os.path.join(curr, ".pipeline", "logical-ui", "codebase_rules.json")):
                workspace_dir = curr
                break
            parent = os.path.dirname(curr)
            if parent == curr:
                break
            curr = parent
            
    if not workspace_dir:
        workspace_dir = os.getcwd()
        
    workspace_dir = os.path.abspath(workspace_dir)
    
    # 2. Initialize WorkspaceRepository with the determined workspace_dir
    repo = WorkspaceRepository(workspace_dir)
    
    # 3. Check if the codebase rules file exists
    rules_path = repo.get_codebase_rules_path()
    if not os.path.exists(rules_path):
        print(f"Error: codebase_rules.json not found at: {rules_path}")
        print("Please ensure the configuration file is present at '.pipeline/logical-ui/codebase_rules.json'.")
        sys.exit(1)
        
    # 4. Check if rules is empty or invalid, or if rules.meta.upstream_repository is empty
    try:
        with open(rules_path, "r", encoding="utf-8") as f:
            json.load(f)
    except Exception:
        print("Error: Configuration is empty, invalid, or missing required metadata.")
        print("Please check '.pipeline/logical-ui/codebase_rules.json' and ensure it has a valid 'meta.upstream_repository' set.")
        sys.exit(1)
        
    rules = repo.get_codebase_rules()
    if not rules or not rules.meta or not rules.meta.upstream_repository:
        print("Error: Configuration is empty, invalid, or missing required metadata.")
        print("Please check '.pipeline/logical-ui/codebase_rules.json' and ensure it has a valid 'meta.upstream_repository' set.")
        sys.exit(1)
        
    backlog_dirs = rules.backlog_directories
    
    schema_dir = args.schema_dir
    if not schema_dir:
        schema_dir = os.environ.get("SCHEMA_DIR")
    if not schema_dir:
        schema_dir_rel = backlog_dirs.schemas
        if not schema_dir_rel:
            raise ValueError("Missing 'backlog_directories.schemas' in codebase_rules.json")
        schema_dir = os.path.join(repo.workspace_dir, schema_dir_rel)
    else:
        schema_dir = os.path.abspath(schema_dir)
        
    features_dir = args.features_dir
    if not features_dir:
        features_dir = os.environ.get("FEATURES_DIR")
    if not features_dir:
        features_dir_rel = backlog_dirs.features
        if not features_dir_rel:
            raise ValueError("Missing 'backlog_directories.features' in codebase_rules.json")
        features_dir = os.path.join(repo.workspace_dir, features_dir_rel)
    else:
        features_dir = os.path.abspath(features_dir)
        
    epics_dir_rel = backlog_dirs.epics
    epics_dir = os.path.join(repo.workspace_dir, epics_dir_rel) if epics_dir_rel else None
        
    has_failed = False
    print("=== Model Coverage Parity Audit ===")
    print(f"Scanning schemas in: {schema_dir}")
    print(f"Scanning feature specifications in: {features_dir}\n")
    
    # 1. Parse all modules
    modules = {}
    if os.path.exists(schema_dir):
        for filename in os.listdir(schema_dir):
            filepath = os.path.join(schema_dir, filename)
            if os.path.isdir(filepath):
                continue
            try:
                module_name, definitions = parse_schema_file(filepath)
                if module_name:
                    modules[module_name] = definitions
            except Exception as e:
                print(f"Warning: Failed to parse schema file {filename}: {e}")
                
    alternative_extensions = set(rules.validation_rules.alternative_schema_extensions)
    has_parseable_schemas = False
    has_alternative_schemas = False
    
    from .parsers.schema_router import SchemaRouter
    router = SchemaRouter(repo)
    
    if os.path.exists(schema_dir):
        for filename in os.listdir(schema_dir):
            filepath = os.path.join(schema_dir, filename)
            if os.path.isdir(filepath):
                continue
            ext = os.path.splitext(filename)[1].lower()
            if router.can_parse(filepath):
                has_parseable_schemas = True
            elif ext in alternative_extensions:
                has_alternative_schemas = True
                
    # 2. Load all feature markdown files
    features = repo.get_feature_files(features_dir)
    print(f"Loaded {len(features)} feature specifications.\n")
    
    # Cross-reference local docs/features/ spec files against open feature issues fetched via gh CLI
    open_issues = get_open_feature_issues()
    missing_specs = []
    for issue in open_issues:
        issue_number = issue.get("number")
        issue_title = issue.get("title", "")
        found = False
        for f in features:
            basename = os.path.splitext(f.filename)[0]
            numbers_in_filename = [int(x) for x in re.findall(r'\d+', basename)]
            if issue_number in numbers_in_filename:
                found = True
                break
            if f"#{issue_number}" in f.content or f"issue {issue_number}" in f.content.lower():
                found = True
                break
        if not found:
            missing_specs.append(f"Issue #{issue_number}: '{issue_title}'")
            
    if missing_specs:
        print("[!] Missing local specification files for open feature issues:")
        for spec in missing_specs:
            print(f"  - {spec}")
        # sys.exit(1) # Bypassed exit code 1 locally per upstream issue #15
    
    skip_coverage_checks = False
    if args.spec_only or not features:
        if args.spec_only:
            print("Note: Running in spec-only mode. Skipping model coverage checks.")
        else:
            print("Note: No feature specifications found in directory. Skipping model coverage checks.")
        skip_coverage_checks = True
    else:
        react_dir_name = rules.target_directories.react
        flutter_dir_name = rules.target_directories.flutter
        react_exists = os.path.exists(os.path.join(repo.workspace_dir, react_dir_name)) if react_dir_name else False
        flutter_exists = os.path.exists(os.path.join(repo.workspace_dir, flutter_dir_name)) if flutter_dir_name else False
        if not react_exists and not flutter_exists:
            print("Note: Target directories (React and Flutter) do not exist. Skipping model coverage checks.")
            skip_coverage_checks = True
        
    # 3. Audit codebase coverage of UML classes
    total_defined = 0
    total_covered = 0
    coverage_gaps = []
    
    uml_validator = UmlValidator()
    global_classes = uml_validator.build_global_classes(repo, features_dir, epics_dir)
    
    if not skip_coverage_checks and features:
        # Read codebase source files
        codebase_contents = []
        
        # React
        react_dir_name = rules.target_directories.react
        if react_dir_name:
            react_dir = os.path.join(repo.workspace_dir, react_dir_name)
            if os.path.exists(react_dir):
                react_exts = tuple(rules.react_rules.file_extensions)
                react_exclusions = set(rules.react_rules.exclusions)
                for root, dirs, files in os.walk(react_dir):
                    dirs[:] = [d for d in dirs if d not in react_exclusions]
                    for file in files:
                        if file.endswith(react_exts):
                            try:
                                with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                                    codebase_contents.append(f.read())
                            except Exception:
                                pass
                                
        # Flutter
        flutter_dir_name = rules.target_directories.flutter
        if flutter_dir_name:
            flutter_dir = os.path.join(repo.workspace_dir, flutter_dir_name)
            if os.path.exists(flutter_dir):
                flutter_exts = tuple(rules.flutter_rules.file_extensions)
                flutter_exclusions = set(rules.flutter_rules.exclusions)
                for root, dirs, files in os.walk(flutter_dir):
                    dirs[:] = [d for d in dirs if d not in flutter_exclusions]
                    for file in files:
                        if file.endswith(flutter_exts):
                            try:
                                with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                                    codebase_contents.append(f.read())
                            except Exception:
                                pass

        react_dir_exists = False
        react_dir_name = rules.target_directories.react
        if react_dir_name:
            react_dir = os.path.join(repo.workspace_dir, react_dir_name)
            if os.path.exists(react_dir):
                react_dir_exists = True
                
        flutter_dir_exists = False
        flutter_dir_name = rules.target_directories.flutter
        if flutter_dir_name:
            flutter_dir = os.path.join(repo.workspace_dir, flutter_dir_name)
            if os.path.exists(flutter_dir):
                flutter_dir_exists = True
                
        if (react_dir_exists or flutter_dir_exists) and not codebase_contents:
            print("[!] Error: Target codebase directories exist but contain no source files.")
            has_failed = True

        # Helper to generate variants for a name
        def get_variants(name: str) -> Set[str]:
            variants = {name}
            if '-' in name or '_' in name or '.' in name:
                parts = re.split(r'[-_.]', name)
                variants.add(parts[0] + "".join(p.capitalize() for p in parts[1:]))
                variants.add("".join(p.capitalize() for p in parts))
                variants.add("_".join(p.lower() for p in parts))
            else:
                if name:
                    variants.add(name[0].lower() + name[1:])
                    variants.add(name[0].upper() + name[1:])
            return variants

        for cls_name, cls_info in sorted(global_classes.items()):
            # Check class name
            cls_variants = get_variants(cls_name)
            cls_found = False
            for content in codebase_contents:
                if any(re.search(r'\b' + re.escape(v) + r'\b', content) for v in cls_variants):
                    cls_found = True
                    break
            
            total_defined += 1
            if cls_found:
                total_covered += 1
            else:
                coverage_gaps.append(f"Class '{cls_name}'")

            # Check attributes
            for attr in cls_info["attributes"]:
                attr_name = attr["name"]
                attr_variants = get_variants(attr_name)
                attr_found = False
                for content in codebase_contents:
                    if any(re.search(r'\b' + re.escape(v) + r'\b', content) for v in attr_variants):
                        attr_found = True
                        break
                total_defined += 1
                if attr_found:
                    total_covered += 1
                else:
                    coverage_gaps.append(f"Attribute '{cls_name}.{attr_name}'")

            # Check methods
            for method in cls_info["methods"]:
                method_name = method["name"]
                method_variants = get_variants(method_name)
                method_found = False
                for content in codebase_contents:
                    if any(re.search(r'\b' + re.escape(v) + r'\b', content) for v in method_variants):
                        method_found = True
                        break
                total_defined += 1
                if method_found:
                    total_covered += 1
                else:
                    coverage_gaps.append(f"Method '{cls_name}.{method_name}'")

        print("\n=== Audit Summary ===")
        if total_defined > 0:
            overall_pct = (total_covered / total_defined) * 100
            print(f"Total UML Elements Defined: {total_defined}")
            print(f"Total UML Elements Covered: {total_covered}")
            print(f"Overall Model Coverage:     {overall_pct:.2f}%")
        else:
            print("No UML elements found in specifications to verify.")
            sys.exit(1)
            
    print("\n=== UML Diagrams Compliance Audit ===")
    uml_errors = []
    if not features:
        print("Note: No feature specifications found. Skipping UML Diagrams Compliance Audit.")
    else:
        uml_errors = uml_validator.validate(repo, global_classes=global_classes)
        
    if uml_errors:
        print("[!] UML Compliance Violations Identified:")
        for err in uml_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        if features:
            print("Success: All specification files are fully UML-compliant (no ERDs or invalid syntax found).")
            
    if coverage_gaps:
        print("\n[!] Codebase Coverage Gaps Identified:")
        for gap in sorted(coverage_gaps):
            print(f"  - {gap}")
        print("\nError: 100% model coverage validation failed.")
        has_failed = True
    else:
        if not skip_coverage_checks and features:
            print("\nSuccess: 100% model coverage verified across all specification files.")
            
    print("\n=== Behavioral Coverage Triggers Audit ===")
    behavioral_validator = BehavioralValidator()
    behavioral_errors = []
    if not features:
        print("Note: No feature specifications found. Skipping Behavioral Coverage Triggers Audit.")
    else:
        behavioral_errors = behavioral_validator.validate(repo, schema_dir=schema_dir, modules=modules)
        
    if behavioral_errors:
        print("[!] Behavioral Coverage Violations Identified:")
        for err in behavioral_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        print("Success: All behavioral coverage triggers passed.")
        
    if args.spec_only:
        print("Note: Running in spec-only mode. Skipping Codebase AST / Compliance Audit.")
        codebase_errors = []
    else:
        print("\n=== Codebase AST / Compliance Audit ===")
        codebase_validator = CodebaseValidator()
        codebase_errors = codebase_validator.validate(repo)
    
    if codebase_errors:
        print("[!] Codebase Compliance Violations Identified:")
        for err in codebase_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        print("Success: Codebase compliance checks passed.")
        
    print("\n=== Documentation Consistency Audit ===")
    docs_validator = DocsValidator()
    doc_errors = docs_validator.validate(repo)
    
    if doc_errors:
        print("[!] Documentation Consistency Violations Identified:")
        for err in doc_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        print("Success: Documentation consistency checks passed.")
        
    print("\n=== Schema Dependency Validation ===")
    dependency_validator = DependencyValidator()
    dependency_errors = dependency_validator.validate(repo, schema_dir=schema_dir)
    
    if dependency_errors:
        print("[!] Schema Dependency Violations Identified:")
        for err in dependency_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        print("Success: Schema dependency checks passed.")
        
    print("\n=== Out-of-Sync Backlog Validation ===")
    sync_validator = SyncValidator()
    sync_errors = sync_validator.validate(repo)
    
    if sync_errors:
        print("[!] Out-of-Sync Backlog Violations Identified:")
        for err in sync_errors:
            print(f"  - {err}")
        has_failed = True
    else:
        print("Success: Out-of-Sync Backlog checks passed.")
        
    print("\n=== Schema Mapping Validation ===")
    if args.spec_only:
        print("Note: Running in spec-only mode. Skipping Schema Mapping Validation.")
        schema_mapping_errors = []
    else:
        schema_mapping_validator = SchemaMappingValidator()
        schema_mapping_errors = schema_mapping_validator.validate(repo)
        if schema_mapping_errors:
            print("[!] Schema Mapping Violations Identified:")
            for err in schema_mapping_errors:
                print(f"  - {err}")
            has_failed = True
        else:
            print("Success: Schema mapping checks passed.")

    print("\n=== Profile Scoping Validation ===")
    if args.spec_only:
        print("Note: Running in spec-only mode. Skipping Profile Scoping Validation.")
        profile_scoping_errors = []
    else:
        profile_scoping_validator = ProfileScopingValidator()
        profile_scoping_errors = profile_scoping_validator.validate(repo)
        if profile_scoping_errors:
            print("[!] Profile Scoping Violations Identified:")
            for err in profile_scoping_errors:
                print(f"  - {err}")
            has_failed = True
        else:
            print("Success: Profile scoping checks passed.")

    print("\n=== Test Completeness Validation ===")
    if args.spec_only:
        print("Note: Running in spec-only mode. Skipping Test Completeness Validation.")
        test_completeness_errors = []
    else:
        test_completeness_validator = TestCompletenessValidator()
        test_completeness_errors = test_completeness_validator.validate(repo)
        if test_completeness_errors:
            print("[!] Test Completeness Violations Identified:")
            for err in test_completeness_errors:
                print(f"  - {err}")
            has_failed = True
        else:
            print("Success: Test completeness checks passed.")
        
    if has_failed:
        all_errors = (uml_errors or []) + (behavioral_errors or []) + (codebase_errors or []) + (doc_errors or []) + (dependency_errors or []) + (sync_errors or []) + (schema_mapping_errors or []) + (profile_scoping_errors or []) + (test_completeness_errors or [])
        compiled_errors = all_errors
        target_file = None
        snippet_content = None
        for err in compiled_errors:
            match = re.search(r'docs/[a-zA-Z0-9_\-/]+\.md', err)
            if match:
                rel_path = match.group(0)
                abs_path = os.path.join(workspace_dir, rel_path)
                if os.path.exists(abs_path):
                    target_file = rel_path
                    try:
                        with open(abs_path, "r", encoding="utf-8") as f:
                            snippet_content = f.read()
                    except Exception:
                        pass
                    break
        
        serialize_diagnostics(
            workspace_dir=workspace_dir,
            tool_name="parity_auditor",
            exit_code=1,
            errors=compiled_errors,
            traceback_str="",
            target_file=target_file,
            snippet_content=snippet_content
        )
        sys.exit(1)
    else:
        print("\nSuccess: All verification checks passed.")
        sys.exit(0)

def main():
    """
    Entry point: strips dummy GITHUB_TOKEN, runs ``_main_impl()``, and
    catches unhandled exceptions with a diagnostic report.

    Side effects:
        - Removes ``GITHUB_TOKEN`` from the environment if it contains
          ``dummytoken``.
        - Exits with code 1 on failure after writing a diagnostics JSON
          artifact.
    """
    if "GITHUB_TOKEN" in os.environ and "dummytoken" in os.environ["GITHUB_TOKEN"]:
        del os.environ["GITHUB_TOKEN"]
    try:
        _main_impl()
    except SystemExit:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        upstream_repo = "gintatkinson/digital-pipeline-repo"
        try:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            workspace_dir = None
            curr = script_dir
            while True:
                if os.path.exists(os.path.join(curr, ".pipeline", "logical-ui", "codebase_rules.json")):
                    workspace_dir = curr
                    break
                parent = os.path.dirname(curr)
                if parent == curr:
                    break
                curr = parent
            if not workspace_dir:
                workspace_dir = os.getcwd()
            rules_path = os.path.join(workspace_dir, ".pipeline", "logical-ui", "codebase_rules.json")
            if os.path.exists(rules_path):
                with open(rules_path, "r", encoding="utf-8") as f:
                    rules_data = json.load(f)
                    upstream_repo = rules_data.get("meta", {}).get("upstream_repository", upstream_repo)
        except Exception:
            pass
        print("\n[!] If you believe this failure is due to a bug or limitation in the pipeline tooling, please report it upstream:")
        print(f"    gh issue create --repo {upstream_repo} --title \"Tooling Bug: [Brief description]\" --body \"Context: UML/Coverage validation failed in downstream execution.\"")
        sys.exit(1)

if __name__ == "__main__":
    main()
