import os
import re
import shutil
import sys
from datetime import datetime

import pandas as pd

# ==============================================================================
# SECTION 1: CONFIGURATION
# Modify this section to match your Excel column headers exactly.
# ==============================================================================
CONFIG = {
    # File Paths (Change these to your actual paths)
    "INPUT_EXCEL_PATH": "pm-q6-v1.3.xlsx",
    "OUTPUT_FOLDER": "02_Data_Imports",
    # Excel Column Mapping (Key: Internal Variable, Value: Excel Header String)
    "COL_ID": "编号",  # The unique ID column (Column A)
    "COL_PRODUCT": "产品名称",  # e.g., Q6
    "COL_PHASE": "阶段",  # e.g., FPGA, Design
    "COL_TASK": "任务",  # The main task name
    "COL_PREDECESSORS": "前置依赖任务",  # Dependency IDs (e.g., "18, 31")
    "COL_SEQUENCE": "顺序",  # Developer execution order/priority
    "COL_OWNER": "负责人",  # Task assignees
    "COL_STATUS": "完成情况",  # Completion status
    "COL_PLAN_START": "计划开始",
    "COL_PLAN_END": "计划完成",
    "COL_ACTUAL_START": "实际开始",
    "COL_ACTUAL_END": "实际完成",
    # Separator used in Excel cells (e.g., "UserA, UserB")
    "SEPARATOR": ",",
}

# ==============================================================================
# SECTION 2: HELPER FUNCTIONS
# Utility functions for data cleaning and formatting.
# ==============================================================================


def clean_output_directory(directory_path):
    """
    Safely removes all files in the target directory to prepare for fresh import.
    Creates the directory if it does not exist.
    """
    if os.path.exists(directory_path):
        try:
            shutil.rmtree(directory_path)
            os.makedirs(directory_path)
            print(f"[INFO] Cleaned directory: {directory_path}")
        except Exception as e:
            print(f"[ERROR] Failed to clean directory: {e}")
            sys.exit(1)
    else:
        os.makedirs(directory_path)
        print(f"[INFO] Created directory: {directory_path}")


def format_date(date_obj):
    """
    Standardizes Excel dates to YYYY-MM-DD string format.
    Returns empty string if the date is invalid or missing.
    """
    if pd.isnull(date_obj):
        return ""
    try:
        # Handle cases where Excel might export as string or datetime object
        return pd.to_datetime(date_obj).strftime("%Y-%m-%d")
    except:
        return ""


def sanitize_filename(filename):
    """
    Removes illegal characters from filenames to prevent OS errors.
    """
    # Keep only alphanumerics, spaces, dashes, underscores, and dots
    safe_name = "".join([c for c in str(filename) if c.isalnum() or c in " -_."])
    return safe_name.strip()


def parse_multi_value_cell(cell_value):
    """
    Splits a cell string by the comma separator.
    Returns a list of stripped strings.
    """
    if pd.isnull(cell_value) or str(cell_value).strip() == "":
        return []

    # Convert to string and split by the configured separator
    raw_str = str(cell_value)
    # Split by comma (half-width) as requested
    items = raw_str.split(CONFIG["SEPARATOR"])
    return [item.strip() for item in items if item.strip()]


# ==============================================================================
# SECTION 3: CORE LOGIC
# ==============================================================================


def build_task_index(df):
    """
    PASS 1: Scan the Excel file to build a map of {ID: Task_Name}.
    This is crucial for resolving 'Predecessors' (which are IDs) into links.
    """
    task_map = {}
    print("[INFO] Pass 1: Building Task ID Index...")

    for index, row in df.iterrows():
        # Get ID (Column A)
        raw_id = row.get(CONFIG["COL_ID"])
        # Get Task Name
        raw_name = row.get(CONFIG["COL_TASK"])

        if pd.notna(raw_id) and pd.notna(raw_name):
            # Convert ID to string integer (remove decimals if any)
            task_id = str(raw_id).split(".")[0].strip()
            task_name = str(raw_name).strip()
            task_map[task_id] = task_name

    print(f"[INFO] Indexed {len(task_map)} tasks.")
    return task_map


def generate_markdown_files(df, task_map):
    """
    PASS 2: Iterate through rows again to generate Markdown files.
    """
    print("[INFO] Pass 2: Generating Markdown files...")
    count = 0

    for index, row in df.iterrows():
        # 1. Extract Basic Info
        task_name = str(row.get(CONFIG["COL_TASK"], "Untitled")).strip()
        if not task_name or task_name.lower() == "nan":
            continue  # Skip empty rows

        # Clean ID
        task_id = str(row.get(CONFIG["COL_ID"], "")).split(".")[0].strip()

        # 2. Extract and Format Dates
        plan_start = format_date(row.get(CONFIG["COL_PLAN_START"]))
        plan_end = format_date(row.get(CONFIG["COL_PLAN_END"]))
        act_start = format_date(row.get(CONFIG["COL_ACTUAL_START"]))
        act_end = format_date(row.get(CONFIG["COL_ACTUAL_END"]))

        # 3. Handle Assignees (Owners) - AS STRINGS, NOT LINKS
        # We store them as a YAML list of strings to keep the vault clean.
        owners_list = parse_multi_value_cell(row.get(CONFIG["COL_OWNER"]))
        # Format for YAML: ["Name1", "Name2"]
        owners_yaml = str(owners_list).replace("'", '"')
        owners_display = ", ".join(owners_list)  # For body text

        # 4. Handle Predecessors (Dependencies) - AS LINKS
        # Converts IDs "18, 31" into "[[Task Name 18]], [[Task Name 31]]"
        pred_ids = parse_multi_value_cell(row.get(CONFIG["COL_PREDECESSORS"]))
        pred_links = []

        for pid in pred_ids:
            # Lookup the name using the ID from Pass 1
            pid_clean = pid.split(".")[0].strip()
            if pid_clean in task_map:
                target_name = task_map[pid_clean]
                pred_links.append(f"[[{target_name}]]")
            else:
                # If ID not found, just keep the ID (or ignore)
                pass

        # Format for YAML list: [[Task A]], [[Task B]]
        # We join manually to ensure correct Obsidian link syntax in YAML
        blocked_by_yaml = f"[{', '.join(pred_links)}]"

        # 5. Handle Other Metadata
        product = str(row.get(CONFIG["COL_PRODUCT"], "")).strip()
        phase = str(row.get(CONFIG["COL_PHASE"], "")).strip()
        status = str(row.get(CONFIG["COL_STATUS"], "Todo")).strip()
        sequence = str(row.get(CONFIG["COL_SEQUENCE"], "")).split(".")[0].strip()

        # 6. Construct Markdown Content
        # Note: We use 'assignees' (plural) for the list of people strings.
        # Note: We use 'blocked_by' for the list of task links (Obsidian Projects compatible).
        md_content = f"""---
type: task
task_id: "{task_id}"
task_name: "{task_name}"
status: {status}
priority_sequence: "{sequence}"
product: "{product}"
phase: "{phase}"
assignees: {owners_yaml}
blocked_by: {blocked_by_yaml}
plan_start: {plan_start}
plan_end: {plan_end}
act_start: {act_start}
act_end: {act_end}
created_at: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
---

# {task_name}

> **Product**: {product} | **Phase**: {phase}
> **Owner**: {owners_display if owners_display else "Unassigned"}

## Schedule
| Type | Start | End |
| :--- | :--- | :--- |
| **Plan** | {plan_start} | {plan_end} |
| **Actual** | {act_start} | {act_end} |

## Dependencies
**Waiting for:**
{chr(10).join([f"- {link}" for link in pred_links]) if pred_links else "- None"}

"""
        # 7. Write File
        file_name = f"{sanitize_filename(task_name)}.md"
        file_path = os.path.join(CONFIG["OUTPUT_FOLDER"], file_name)

        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(md_content)
            count += 1
        except Exception as e:
            print(f"[WARN] Could not write file {file_name}: {e}")

    print(f"[SUCCESS] Generated {count} Markdown files in '{CONFIG['OUTPUT_FOLDER']}'")


# ==============================================================================
# SECTION 4: MAIN ENTRY POINT
# ==============================================================================


def main():
    print("===================================================")
    print("   Excel to Obsidian Converter (Strict Logic)      ")
    print("===================================================")

    # 1. Validate Input File
    excel_path = CONFIG["INPUT_EXCEL_PATH"]
    if not os.path.exists(excel_path):
        print(f"[ERROR] Excel file not found at: {excel_path}")
        print("Please check the 'INPUT_EXCEL_PATH' in CONFIG section.")
        return

    # 2. Load Excel Data
    try:
        # Read Excel, ensuring strict string interpretation for IDs to avoid '1.0' issues
        df = pd.read_excel(excel_path, dtype=str)
        # Clean up 'nan' string values that pandas might produce for empty cells
        df = df.fillna("")
        print(f"[INFO] Successfully loaded Excel: {excel_path}")
    except Exception as e:
        print(f"[ERROR] Failed to read Excel: {e}")
        return

    # 3. Clean Output Directory
    clean_output_directory(CONFIG["OUTPUT_FOLDER"])

    # 4. Execution Pipeline
    # Step A: Build the ID map first (for dependencies)
    task_index = build_task_index(df)

    # Step B: Generate the content
    generate_markdown_files(df, task_index)

    print("===================================================")
    print("Done.")


if __name__ == "__main__":
    main()
