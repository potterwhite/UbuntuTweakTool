import pandas as pd
import os
import shutil
import re
import sys
from datetime import datetime

# ==============================================================================
# SECTION 1: CONFIGURATION (配置区 - 保持你之前的修改)
# ==============================================================================
CONFIG = {
    "INPUT_EXCEL_PATH": "pm-q6-v1.3.xlsx",  # <--- 记得改成你的Excel文件名
    "OUTPUT_FOLDER": "02_Data_Imports",
    "DASHBOARD_FILE": "01_Dashboard/Q6_Markwhen_Gantt-v5.md", # <--- 新增：生成的看板文件路径

    # Excel 列名映射 (按你现在的 Excel 改)
    "COL_ID": "任务编号",           # A列
    "COL_PRODUCT": "产品名称",      # B列
    "COL_PHASE": "阶段",           # C列
    "COL_TASK": "任务",            # D列
    "COL_PREDECESSORS": "前置依赖任务", # E列
    "COL_SEQUENCE": "顺序",
    "COL_OWNER": "负责人",
    "COL_STATUS": "完成情况",
    "COL_PLAN_START": "计划开始",
    "COL_PLAN_END": "计划完成",
    "COL_ACTUAL_START": "实际开始",
    "COL_ACTUAL_END": "实际完成",
    
    "SEPARATOR": "," 
}

# ==============================================================================
# SECTION 2: HELPER FUNCTIONS (辅助函数 - 不变)
# ==============================================================================
def clean_output_directory(directory_path):
    if os.path.exists(directory_path):
        try:
            shutil.rmtree(directory_path)
            os.makedirs(directory_path)
        except Exception as e:
            pass
    else:
        os.makedirs(directory_path)

def format_date(date_obj):
    if pd.isnull(date_obj): return ""
    try: return pd.to_datetime(date_obj).strftime('%Y-%m-%d')
    except: return ""

def sanitize_filename(filename):
    return "".join([c for c in str(filename) if c.isalnum() or c in " -_."]).strip()

def parse_multi_value_cell(cell_value):
    if pd.isnull(cell_value) or str(cell_value).strip() == "": return []
    raw_str = str(cell_value)
    items = raw_str.split(CONFIG["SEPARATOR"])
    return [item.strip() for item in items if item.strip()]

# ==============================================================================
# SECTION 3: MARKWHEN GENERATOR (新增的核心功能！)
# ==============================================================================
def generate_markwhen_view(df):
    """
    PASS 3: 生成 Markwhen 语法的甘特图代码
    """
    print("[INFO] Pass 3: Generating Markwhen Dashboard...")
    
    # 1. 准备 Markwhen 的头部配置 (定义颜色)
    mw_content = """---
type: markwhen
---

```markwhen
title: Q6 研发项目全景甘特图
description: 由 Python 脚本自动生成，请勿手动修改

# 颜色定义 (你可以自己改这些十六进制颜色)
#done: #2ecc71
#active: #3498db
#delayed: #e74c3c
#todo: #95a5a6
#milestone: #f1c40f

"""
    
    # 2. 按“阶段” (Phase) 分组
    # 我们先过滤掉没有日期的任务，因为 Markwhen 必须要有日期才能画图
    valid_df = df.dropna(subset=[CONFIG["COL_PLAN_START"]])
    
    # 获取所有唯一的阶段，按原本 Excel 出现的顺序排序
    phases = valid_df[CONFIG["COL_PHASE"]].unique()

    for phase in phases:
        phase_name = str(phase).strip()
        mw_content += f"\ngroup {phase_name}\n"  # 开始一个分组
        
        # 获取该阶段下的所有任务
        phase_tasks = valid_df[valid_df[CONFIG["COL_PHASE"]] == phase]
        
        for index, row in phase_tasks.iterrows():
            # 获取数据
            task_name = str(row.get(CONFIG["COL_TASK"], "Task")).strip()
            start = format_date(row.get(CONFIG["COL_PLAN_START"]))
            end = format_date(row.get(CONFIG["COL_PLAN_END"]))
            status = str(row.get(CONFIG["COL_STATUS"], "")).strip()
            
            # 如果没有结束时间，默认等于开始时间（变成单点时间）
            if not end: end = start
            
            # 确定标签颜色
            tag = "#todo"
            if "完成" in status: tag = "#done"
            elif "进行" in status: tag = "#active"
            elif "未开始" in status: tag = "#todo"
            
            # 检查延期 (如果今天 > 计划结束 且 未完成)
            today = datetime.now().strftime('%Y-%m-%d')
            if end < today and "完成" not in status:
                tag = "#delayed"

            # 写入 Markwhen 语法: date-range: task name #tags
            # 语法示例: 2025-01-01 / 2025-01-05: 任务名称 #done
            mw_content += f"{start} / {end}: {task_name} {tag}\n"
            
        mw_content += "endGroup\n" # 结束分组

    mw_content += "```\n"

    # 3. 写入文件
    # 确保目录存在
    output_path = os.path.join(CONFIG["OUTPUT_FOLDER"], "..", CONFIG["DASHBOARD_FILE"])
    # output_path = os.path.join(CONFIG["OUTPUT_FOLDER"], CONFIG["DASHBOARD_FILE"])
    output_path = os.path.normpath(output_path) # 修复路径中的 ..
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(mw_content)
        
    print(f"[SUCCESS] Markwhen chart generated at: {CONFIG['DASHBOARD_FILE']}")

# ==============================================================================
# SECTION 4: MAIN ENTRY POINT
# ==============================================================================
def main():
    print("===================================================")
    print("   Excel to Obsidian + Markwhen Converter          ")
    print("===================================================")

    excel_path = CONFIG["INPUT_EXCEL_PATH"]
    if not os.path.exists(excel_path):
        print(f"[ERROR] Excel file not found: {excel_path}")
        return

    try:
        df = pd.read_excel(excel_path, dtype=str)
        # 填充 NaN，防止报错
        df = df.fillna("") 
    except Exception as e:
        print(f"[ERROR] Failed to read Excel: {e}")
        return

    # Pass 1 & 2 (生成 Markdown 小文件，逻辑不变，保留之前功能)
    clean_output_directory(CONFIG["OUTPUT_FOLDER"])
    # 这里为了脚本简洁，我省略了 Task Index 和 Generate Files 的代码
    # 如果你之前的脚本跑通了，请把上面的 generate_markwhen_view 函数复制到你现有脚本里
    # 然后在 main() 里调用它。
    # 为了保证这个脚本能独立运行，我这里简单写一下调用逻辑：
    
    # 假设你保留了之前的 generate_markdown_files 函数，这里调用它
    # generate_markdown_files(df, build_task_index(df)) <--- 你之前的逻辑
    
    # Pass 3: 生成 Markwhen
    generate_markwhen_view(df)

    print("===================================================")
    print("Done.")

if __name__ == "__main__":
    main()