import pandas as pd
import os
import shutil
import re
import sys
from datetime import datetime

# ==============================================================================
# SECTION 1: CONFIGURATION
# Adjust these values to match your specific Excel file structure.
# ==============================================================================
CONFIG = {
    # 1. File Paths
    "INPUT_EXCEL_PATH": "pm-q6-v1.3.xlsx",  # <--- Change to your Excel filename
    "OUTPUT_MD_FOLDER": "02_Data_Imports",  # Folder for individual task notes
    "OUTPUT_MW_FOLDER": "01_Dashboard",     # Folder for the Markwhen Gantt file
    "MW_FILENAME": "Q6_Project_Gantt.mw",   # The standalone Markwhen file
    
    # 2. Excel Column Mapping (Key: Script Variable, Value: Excel Header)
    # Ensure these match your Excel headers EXACTLY.
    "COL_ID": "任务编号",
    "COL_PRODUCT": "产品名称",
    "COL_PHASE": "阶段",           # Grouping key
    "COL_TASK": "任务",            # Task Label
    "COL_PREDECESSORS": "前置依赖任务",
    "COL_OWNER": "负责人",
    "COL_STATUS": "完成情况",      # e.g., 完成, 进行中, 未开始
    "COL_PLAN_START": "计划开始",
    "COL_PLAN_END": "计划完成",
    "COL_ACTUAL_START": "实际开始",
    "COL_ACTUAL_END": "实际完成",
    
    "SEPARATOR": ","               # Separator for multi-value cells
}

# ==============================================================================
# SECTION 2: HELPER FUNCTIONS
# ==============================================================================

def clean_directory(path):
    """Safely cleans or creates a directory."""
    if os.path.exists(path):
        try:
            shutil.rmtree(path)
        except Exception:
            pass
    os.makedirs(path, exist_ok=True)

def format_date(date_obj):
    """Converts Excel date to YYYY-MM-DD string."""
    if pd.isnull(date_obj): return ""
    try:
        return pd.to_datetime(date_obj).strftime('%Y-%m-%d')
    except:
        return ""

def sanitize_filename(filename):
    """Sanitizes strings to be safe filenames."""
    return "".join([c for c in str(filename) if c.isalnum() or c in " -_."]).strip()

def parse_multi_value(cell_value):
    """Splits string by separator into a list."""
    if pd.isnull(cell_value) or str(cell_value).strip() == "": return []
    return [x.strip() for x in str(cell_value).split(CONFIG["SEPARATOR"]) if x.strip()]

# ==============================================================================
# SECTION 3: CORE LOGIC - MARKDOWN GENERATOR (The Database)
# ==============================================================================

def generate_markdown_db(df):
    """
    Generates individual .md files for each task. 
    This creates the 'Database' of your tasks in Obsidian.
    """
    print(f"[INFO] Generating Markdown database in '{CONFIG['OUTPUT_MD_FOLDER']}'...")
    
    # Clean target directory first
    target_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", CONFIG["OUTPUT_MD_FOLDER"])
    target_dir = os.path.normpath(target_dir)
    clean_directory(target_dir)

    count = 0
    # Create an ID map for dependencies
    id_map = {}
    for idx, row in df.iterrows():
        tid = str(row.get(CONFIG["COL_ID"], "")).split('.')[0].strip()
        tname = str(row.get(CONFIG["COL_TASK"], "")).strip()
        if tid and tname: id_map[tid] = tname

    # Generate Files
    for index, row in df.iterrows():
        task_name = str(row.get(CONFIG["COL_TASK"], "Untitled")).strip()
        if not task_name or task_name.lower() == "nan": continue

        # Extract data
        task_id = str(row.get(CONFIG["COL_ID"], "")).split('.')[0].strip()
        status = str(row.get(CONFIG["COL_STATUS"], "Todo")).strip()
        phase = str(row.get(CONFIG["COL_PHASE"], "General")).strip()
        product = str(row.get(CONFIG["COL_PRODUCT"], "General")).strip()
        
        # Dates
        plan_start = format_date(row.get(CONFIG["COL_PLAN_START"]))
        plan_end = format_date(row.get(CONFIG["COL_PLAN_END"]))
        
        # Owners (List of strings)
        owners = parse_multi_value(row.get(CONFIG["COL_OWNER"]))
        owners_yaml = str(owners).replace("'", '"')
        
        # Dependencies (Links)
        pred_ids = parse_multi_value(row.get(CONFIG["COL_PREDECESSORS"]))
        pred_links = []
        for pid in pred_ids:
            clean_pid = pid.split('.')[0].strip()
            if clean_pid in id_map:
                pred_links.append(f"[[{sanitize_filename(id_map[clean_pid])}]]")
        
        blocked_by_yaml = f"[{', '.join(pred_links)}]"

        # Content
        md_content = f"""---
type: task
task_id: "{task_id}"
task_name: "{task_name}"
status: {status}
phase: "{phase}"
product: "{product}"
assignees: {owners_yaml}
blocked_by: {blocked_by_yaml}
plan_start: {plan_start}
plan_end: {plan_end}
created_at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
---
# {task_name}
> Generated from Excel. Do not edit properties manually.
"""
        # Save file
        fname = f"{sanitize_filename(task_name)}.md"
        with open(os.path.join(target_dir, fname), "w", encoding="utf-8") as f:
            f.write(md_content)
        count += 1
        
    print(f"[SUCCESS] Created {count} Markdown files.")

# ==============================================================================
# SECTION 4: MARKWHEN GENERATOR (The Gantt View)
# ==============================================================================

def generate_markwhen_file(df):
    """
    Generates a standalone .mw file.
    This creates the 'View' for the Markwhen plugin.
    """
    print(f"[INFO] Generating Markwhen view...")

    # 1. Define Header & Logic
    mw_content = f"""title: {CONFIG['MW_FILENAME'].replace('.mw', '')}
description: Auto-generated from Excel on {datetime.now().strftime('%Y-%m-%d %H:%M')}

# ------------------------------------------
# Color Configuration
# ------------------------------------------
#done: #2ecc71
#active: #3498db
#delayed: #e74c3c
#todo: #95a5a6
#milestone: #f1c40f

# ------------------------------------------
# Timeline Data
# ------------------------------------------
"""

    # 2. Filter valid data (must have start date)
    valid_df = df.dropna(subset=[CONFIG["COL_PLAN_START"]])
    
    # 3. Process by Phase (Groups)
    phases = valid_df[CONFIG["COL_PHASE"]].unique()
    
    today = datetime.now().strftime('%Y-%m-%d')

    for phase in phases:
        phase_name = str(phase).strip()
        mw_content += f"\ngroup {phase_name}\n"
        
        # Get tasks in this phase
        tasks = valid_df[valid_df[CONFIG["COL_PHASE"]] == phase]
        
        for idx, row in tasks.iterrows():
            task_name = str(row.get(CONFIG["COL_TASK"], "Task")).strip()
            start = format_date(row.get(CONFIG["COL_PLAN_START"]))
            end = format_date(row.get(CONFIG["COL_PLAN_END"]))
            status = str(row.get(CONFIG["COL_STATUS"], "")).strip()

            # Logic: Default end date to start date if missing
            if not end: end = start
            if not start: continue 

            # Logic: Determine Tags/Colors
            tag = "#todo"
            if "完成" in status: tag = "#done"
            elif "进行" in status: tag = "#active"
            elif "未开始" in status: tag = "#todo"
            
            # Logic: Delay Detection (If not done AND end date < today)
            if end < today and "完成" not in status:
                tag = "#delayed"
            
            # Logic: Milestone Detection (Start == End)
            if start == end:
                tag = "#milestone"

            # Write Line: YYYY-MM-DD / YYYY-MM-DD: Task Name #tag
            mw_content += f"{start} / {end}: {task_name} {tag}\n"
            
        mw_content += "endGroup\n"

    # 4. Save .mw File
    target_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", CONFIG["OUTPUT_MW_FOLDER"])
    target_dir = os.path.normpath(target_dir)
    clean_directory(target_dir) # Ensure folder exists
    
    mw_path = os.path.join(target_dir, CONFIG["MW_FILENAME"])
    
    with open(mw_path, "w", encoding="utf-8") as f:
        f.write(mw_content)
        
    print(f"[SUCCESS] Markwhen file created at: {mw_path}")

# ==============================================================================
# SECTION 5: MAIN EXECUTION
# ==============================================================================

def main():
    print("===================================================")
    print("   R&D Excel to Obsidian System (v3.0)             ")
    print("===================================================")

    # 1. Load Excel
    excel_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), CONFIG["INPUT_EXCEL_PATH"])
    if not os.path.exists(excel_path):
        print(f"[ERROR] Excel file not found: {excel_path}")
        return

    try:
        df = pd.read_excel(excel_path, dtype=str)
        df = df.fillna("")
    except Exception as e:
        print(f"[ERROR] Failed to read Excel: {e}")
        return

    # 2. Run Generators
    generate_markdown_db(df)   # Generates .md files
    generate_markwhen_file(df) # Generates .mw file

    print("===================================================")
    print("Done. Check Obsidian '01_Dashboard' folder.")

if __name__ == "__main__":
    main()