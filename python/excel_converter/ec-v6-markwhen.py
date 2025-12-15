import os
import re
import shutil
import sys
from datetime import datetime, timedelta

import pandas as pd

# ==============================================================================
# SECTION 1: CONFIGURATION
# Adjust these values to match your specific Excel file structure.
# ==============================================================================
CONFIG = {
    # 1. File Paths
    "INPUT_EXCEL_PATH": "/home/james/pm_baytto/docs/main/pm-q6-v20251215.xlsx",  # <--- Change to your Excel filename
    "OUTPUT_MW_FOLDER": "/home/james/syncthing/ObsidianVault/PARA-Vault/2_AREA/05-Area-Job-Baytto/Project_用Obsidian做ProjectManagement系统/products/q6/01_Dashboard",  # Folder for individual task notes
    "OUTPUT_MD_FOLDER": "/home/james/syncthing/ObsidianVault/PARA-Vault/2_AREA/05-Area-Job-Baytto/Project_用Obsidian做ProjectManagement系统/products/q6/02_Data_Imports",  # Folder for the Markwhen Gantt file
    "MW_FILENAME": "Q6_Project_Gantt.mw",  # The standalone Markwhen file
    # 2. Excel Column Mapping (Key: Script Variable, Value: Excel Header)
    # Ensure these match your Excel headers EXACTLY.
    "COL_ID": "任务编号",
    "COL_PRODUCT": "产品名称",
    "COL_PHASE": "阶段",  # Grouping key
    "COL_DURATION": "工作量(天)",  # Grouping key
    "COL_TASK": "任务",  # Task Label
    "COL_PREDECESSORS": "前置依赖任务",
    "COL_OWNER": "负责人",
    "COL_STATUS": "完成情况",  # e.g., 完成, 进行中, 未开始
    "COL_PLAN_START": "计划开始",
    "COL_PLAN_END": "计划完成",
    "COL_ACTUAL_START": "实际开始",
    "COL_ACTUAL_END": "实际完成",
    "SEPARATOR": ",",  # Separator for multi-value cells
}


# ==============================================================================
# SECTION 2: HELPER FUNCTIONS
# ==============================================================================
def func_1_1_clean_directory(path):
    """Safely cleans or creates a directory."""
    if os.path.exists(path):
        try:
            shutil.rmtree(path)
        except Exception:
            pass
    os.makedirs(path, exist_ok=True)


def func_1_2_format_date(date_obj):
    """Converts Excel date to YYYY-MM-DD string."""
    if pd.isnull(date_obj):
        return ""
    try:
        return pd.to_datetime(date_obj).strftime("%Y-%m-%d")
    except:
        return ""


def func_1_3_sanitize_filename(filename):
    """Sanitizes strings to be safe filenames."""
    return "".join([c for c in str(filename) if c.isalnum() or c in " -_."]).strip()


def func_1_4_parse_multi_value(cell_value):
    """Splits string by separator into a list."""
    if pd.isnull(cell_value) or str(cell_value).strip() == "":
        return []
    return [x.strip() for x in str(cell_value).split(CONFIG["SEPARATOR"]) if x.strip()]


def func_1_5_calculate_end_date_from_duration(start_str, duration_val):
    """
    通用计算函数：输入开始日期字符串和工期，返回结束日期字符串。
    Logic:
      - If duration >= 1: End = Start + (Duration - 1)  [Inclusive Logic]
      - If duration < 1:  End = Start                   [Same Day / Milestone]
    """
    # 1. Validate start date
    if not start_str or pd.isnull(start_str) or str(start_str).strip() == "":
        return ""

    # 2. Validate duration
    try:
        days = float(duration_val)
    except (ValueError, TypeError):
        days = 0.0  # 格式错误或空值，默认为0

    # 3. Calculate end date
    try:
        s_date = datetime.strptime(str(start_str).split(" ")[0], "%Y-%m-%d")

        # [FIXED LOGIC]
        # 如果工期是 3 天 (Dec 1, 2, 3)，数学上应该加 2 天 (Dec 1 + 2 = Dec 3)
        # 如果工期是 1 天 (Dec 1)，数学上应该加 0 天 (Dec 1 + 0 = Dec 1)
        # 如果工期是 0 天 (里程碑)，加 0 天

        if days >= 1.0:
            add_days = days - 1.0
        else:
            # 处理工期为 0 或者 0.5 天的情况，不减 1，否则日期会倒退
            add_days = 0.0

        e_date = s_date + timedelta(days=add_days)
        return e_date.strftime("%Y-%m-%d")
    except Exception:
        return start_str


# ==============================================================================
# SECTION 3: CORE LOGIC - MARKDOWN GENERATOR (The Database)
# ==============================================================================


def func_2_1_generate_markdown_db(df):
    """
    Generates individual .md files for each task.
    This creates the 'Database' of your tasks in Obsidian.
    """
    print(f"[INFO] Generating Markdown database in '{CONFIG['OUTPUT_MD_FOLDER']}'...")

    # Clean target directory first
    target_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", CONFIG["OUTPUT_MD_FOLDER"]
    )
    target_dir = os.path.normpath(target_dir)
    func_1_1_clean_directory(target_dir)

    count = 0
    # Create an ID map for dependencies
    id_map = {}
    for idx, row in df.iterrows():
        tid = str(row.get(CONFIG["COL_ID"], "")).split(".")[0].strip()
        tname = str(row.get(CONFIG["COL_TASK"], "")).strip()
        if tid and tname:
            id_map[tid] = tname

    # Generate Files
    for index, row in df.iterrows():
        task_name = str(row.get(CONFIG["COL_TASK"], "Untitled")).strip()
        if not task_name or task_name.lower() == "nan":
            continue

        # Extract data
        task_id = str(row.get(CONFIG["COL_ID"], "")).split(".")[0].strip()
        status = str(row.get(CONFIG["COL_STATUS"], "Todo")).strip()
        phase = str(row.get(CONFIG["COL_PHASE"], "General")).strip()
        product = str(row.get(CONFIG["COL_PRODUCT"], "General")).strip()

        # Dates
        plan_start = func_1_2_format_date(row.get(CONFIG["COL_PLAN_START"]))
        plan_end = func_1_2_format_date(row.get(CONFIG["COL_PLAN_END"]))

        # Owners (List of strings)
        owners = func_1_4_parse_multi_value(row.get(CONFIG["COL_OWNER"]))
        owners_yaml = str(owners).replace("'", '"')

        # Dependencies (Links)
        pred_ids = func_1_4_parse_multi_value(row.get(CONFIG["COL_PREDECESSORS"]))
        pred_links = []
        for pid in pred_ids:
            clean_pid = pid.split(".")[0].strip()
            if clean_pid in id_map:
                pred_links.append(
                    f"[[{func_1_3_sanitize_filename(id_map[clean_pid])}]]"
                )

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
created_at: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
---
# {task_name}
> Generated from Excel. Do not edit properties manually.
"""
        # Save file
        fname = f"{func_1_3_sanitize_filename(task_name)}.md"
        with open(os.path.join(target_dir, fname), "w", encoding="utf-8") as f:
            f.write(md_content)
        count += 1

    print(f"[SUCCESS] Created {count} Markdown files.")


# ==============================================================================
# SECTION 4: MARKWHEN GENERATOR (The Gantt View)
# ==============================================================================


def func_2_2_generate_markwhen_file(df):
    """
    Generates a standalone .mw file.
    This creates the 'View' for the Markwhen plugin.
    """
    print("[INFO] Generating Markwhen view...")

    # 1. Define Header & Logic
    mw_content = f"""title: {CONFIG["MW_FILENAME"].replace(".mw", "")}
description: Auto-generated from Excel on {datetime.now().strftime("%Y-%m-%d %H:%M")}

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
    # 2. Filter valid data (must have plan_start and duration)
    required_first = CONFIG["COL_PLAN_START"]
    required_second = CONFIG["COL_DURATION"]
    valid_df = df[
        (df[required_first].astype(str).str.strip() != "")
        & (df[required_second].astype(str).str.strip() != "")
    ]

    dropped_count = len(df) - len(valid_df)
    if dropped_count > 0:
        print(f"[INFO] 过滤掉 {dropped_count} 行无效数据 (缺少计划时间或工作量)")

    # filter the duration number, must be positive integer
    duration_numeric = pd.to_numeric(valid_df[required_second], errors="coerce")
    valid_df = valid_df[duration_numeric > 0]

    # 3. Process by Phase (Groups)
    phases = valid_df[CONFIG["COL_PHASE"]].unique()

    today = datetime.now().strftime("%Y-%m-%d")

    for phase in phases:
        phase_name = str(phase).strip()
        mw_content += f"\ngroup {phase_name}\n"

        # Get tasks in this phase
        tasks = valid_df[valid_df[CONFIG["COL_PHASE"]] == phase]

        for idx, row in tasks.iterrows():
            task_name = str(row.get(CONFIG["COL_TASK"], "Task")).strip()
            status = str(row.get(CONFIG["COL_STATUS"], "")).strip()

            plan_start = func_1_2_format_date(row.get(CONFIG["COL_PLAN_START"]))
            plan_end = func_1_2_format_date(row.get("Calibrated_Plan_End"))

            actual_start = func_1_2_format_date(row.get(CONFIG["COL_ACTUAL_START"]))
            actual_end = func_1_2_format_date(row.get(CONFIG["COL_ACTUAL_END"]))

            try:
                # task_duration = pd.to_numeric(row[CONFIG["COL_DURATION"]], errors='coerce')
                task_duration = float(row.get(CONFIG["COL_DURATION"], 0.0))
            except Exception as e:
                task_duration = 0.0
                print(f"Error converting duration to float: {e}")

            # Logic: Default plan_end date to plan_start date if missing
            if not plan_start:
                continue
            if not plan_end:
                plan_end = plan_start

            # Logic: from now on, there are no plan and actual dates but only draw dates(draw_start, draw_end)
            draw_start = ""
            draw_end = ""
            tag = "#todo"

            if actual_start:
                draw_start = actual_start
                # have-actual_start
                if not actual_end:
                    # b. have-actual_start, no-actual_end
                    try:
                        # s_date = datetime.strptime(actual_start, "%Y-%m-%d")
                        # e_date = s_date + timedelta(days=task_duration)
                        # draw_end = e_date.strftime("%Y-%m-%d")
                        draw_end = func_1_5_calculate_end_date_from_duration(actual_start, task_duration)
                    except Exception as e:
                        print(f"[WARN] Date calc failed for {task_name}: {e}")
                        draw_end = draw_start
                    # ----------------
                    print(f"plan_end = {plan_end}, today = {today}")
                    if plan_end < today:
                        tag = "#delayed"
                    else:
                        tag = "#active"
                else:
                    # d. have-actual_start, have-actual_end
                    draw_end = actual_end
                    # ----------------
                    tag = "#done"
            else:
                # no-actual_start
                # a. no-actual_start, no-actual_end
                if not actual_end:
                    draw_start = plan_start
                    draw_end = plan_end
                    # ----------------
                    if plan_end < today:
                        tag = "#delayed"
                else:
                    # c. no-actual_start, have-actual_end
                    # result: illegal
                    print(f"[WARN] Illegal Data (End without Start): {task_name}")
                    continue

            # Logic: Determine Tags/Colors
            # if not tag:
            #     if "完成" in status:
            #         tag = "#done"
            #     elif "进行" in status:
            #         tag = "#active"
            #     elif "未开始" in status:
            #         tag = "#todo"

            #     # Logic: Delay Detection (If not done AND plan_end date < today)
            #     if plan_end < today and "完成" not in status:
            #         tag = "#delayed"

            # Logic: Milestone Detection (Start == End)
            if draw_start == draw_end:
                tag = "#milestone"

            # Write Line: YYYY-MM-DD / YYYY-MM-DD: Task Name #tag
            mw_content += f"{draw_start} / {draw_end}: {task_name} {tag}\n"

        mw_content += "endGroup\n"

    # 4. Save .mw File
    target_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", CONFIG["OUTPUT_MW_FOLDER"]
    )
    target_dir = os.path.normpath(target_dir)
    func_1_1_clean_directory(target_dir)  # Ensure folder exists

    mw_path = os.path.join(target_dir, CONFIG["MW_FILENAME"])

    with open(mw_path, "w", encoding="utf-8") as f:
        f.write(mw_content)

    print(f"[SUCCESS] Markwhen file created at: {mw_path}")


def func_2_1_data_import_and_preprocess():
    # 1. excel file existance check
    current_dir = os.path.dirname(os.path.abspath(__file__))
    excel_path = os.path.join(current_dir, CONFIG["INPUT_EXCEL_PATH"])
    if not os.path.exists(excel_path):
        print(f"[ERROR] Excel file not found: {excel_path}")
        return

    # 2. Load Excel
    try:
        df = pd.read_excel(excel_path, dtype=str)
        df = df.fillna("")
    except Exception as e:
        print(f"[ERROR] Failed to read Excel: {e}")
        return

    # 3. Pre-process Data
    print("[INFO] Pre-calculating Plan End Dates...")
    df["Calibrated_Plan_End"] = df.apply(
        lambda row: func_1_5_calculate_end_date_from_duration(
            func_1_2_format_date(row.get(CONFIG["COL_PLAN_START"])),
            row.get(CONFIG["COL_DURATION"]),
        ),
        axis=1,
    )

    return df


# ==============================================================================
# SECTION 5: MAIN EXECUTION
# ==============================================================================


def main():
    print("==================================================================")
    print("   R&D Excel Conversion to the Markwhen Plugin for Obsidian      ")
    print("==================================================================")

    df = func_2_1_data_import_and_preprocess()

    # 2. Run Generators
    # func_2_1_generate_markdown_db(df)  # Generates .md files
    func_2_2_generate_markwhen_file(df)  # Generates .mw file

    print("===================================================")
    print("Done. Check Obsidian '01_Dashboard' folder.")


if __name__ == "__main__":
    main()
