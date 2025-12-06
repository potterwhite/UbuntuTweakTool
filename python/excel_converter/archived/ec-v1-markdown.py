import os
import shutil
import sys
from datetime import datetime

import pandas as pd
from colorama import Fore, Style, init

# 初始化颜色
init(autoreset=True)


def print_info(msg):
    print(f"{Fore.CYAN}[INFO] {msg}")


def print_success(msg):
    print(f"{Fore.GREEN}[SUCCESS] {msg}")


def print_warn(msg):
    print(f"{Fore.YELLOW}[WARN] {msg}")


def print_error(msg):
    print(f"{Fore.RED}[ERROR] {msg}")


def get_input_path(prompt_text):
    """获取用户输入的文件路径，支持拖拽进去的路径处理"""
    while True:
        path = input(f"{Fore.BLUE}{prompt_text}{Style.RESET_ALL} ").strip()
        # 处理终端拖拽文件可能产生的引号
        path = path.strip("'").strip('"')
        if not path:
            continue
        # 支持 ~ 符号
        path = os.path.expanduser(path)
        return path


def select_column(columns, field_name):
    """交互式选择列映射"""
    print(f"\n请为 {Fore.MAGENTA}[{field_name}]{Style.RESET_ALL} 选择对应的 Excel 列:")
    for idx, col in enumerate(columns):
        print(f"  {Fore.YELLOW}{idx}{Style.RESET_ALL}: {col}")

    while True:
        try:
            choice = input(f"输入序号 (回车跳过): ").strip()
            if not choice:
                return None
            idx = int(choice)
            if 0 <= idx < len(columns):
                return columns[idx]
            else:
                print_error("序号越界，请重试。")
        except ValueError:
            print_error("请输入有效的数字。")


def clean_directory(directory):
    """清空目录"""
    if not os.path.exists(directory):
        os.makedirs(directory)
        print_success(f"创建目录: {directory}")
        return

    # 安全检查：列出目录里有多少文件
    files = os.listdir(directory)
    if not files:
        return

    print_warn(f"目标目录 {directory} 非空，包含 {len(files)} 个文件。")
    confirm = input(f"{Fore.RED}确认要清空该目录吗? (y/n): {Style.RESET_ALL}").lower()

    if confirm == "y":
        for filename in files:
            file_path = os.path.join(directory, filename)
            try:
                if os.path.isfile(file_path) or os.path.islink(file_path):
                    os.unlink(file_path)
                elif os.path.isdir(file_path):
                    shutil.rmtree(file_path)
            except Exception as e:
                print_error(f"删除失败 {file_path}: {e}")
        print_success("目录已清空。")
    else:
        print_info("操作取消，新文件将覆盖旧文件（如果同名）。")


def format_date(date_obj):
    """鲁棒的日期处理"""
    if pd.isnull(date_obj):
        return ""
    try:
        return pd.to_datetime(date_obj).strftime("%Y-%m-%d")
    except:
        return str(date_obj)


def main():
    print(f"{Fore.GREEN}{'=' * 40}")
    print(f"{Fore.GREEN}   Obsidian 研发项目动态导入工具 v2.0")
    print(f"{Fore.GREEN}{'=' * 40}\n")

    # 1. 获取 Excel 路径
    while True:
        excel_path = get_input_path("请输入 Excel 文件路径 (支持拖拽):")
        if os.path.exists(excel_path) and excel_path.endswith(
            (".xlsx", ".xls", ".csv")
        ):
            break
        print_error("文件不存在或格式不正确，请重试。")

    # 2. 读取 Excel 表头
    try:
        if excel_path.endswith(".csv"):
            df = pd.read_csv(excel_path)
        else:
            df = pd.read_excel(excel_path)
        columns = df.columns.tolist()
        print_success(f"成功读取 Excel，包含 {len(df)} 行数据。")
    except Exception as e:
        print_error(f"读取 Excel 失败: {e}")
        return

    # 3. 动态列映射 (最关键的一步)
    print_info("开始进行列映射配置...")

    # 定义 Obsidian 需要的关键字段
    mapping = {}
    required_fields = {
        "task_name": "任务名称 (必填)",
        "status": "状态 (Status)",
        "start_date": "开始日期 (Start Date)",
        "due_date": "结束日期 (Due Date)",
        "project": "所属项目/产品 (Project)",
        "assignee": "负责人 (Owner)",
    }

    for key, desc in required_fields.items():
        col = select_column(columns, desc)
        if col:
            mapping[key] = col
        elif key == "task_name":
            print_error("任务名称必须指定一列！退出。")
            return

    # 4. 获取输出路径
    default_output = os.path.expanduser(
        "~/syncthing/ObsidianVault/PARA-Vault/2_AREA/05-Area-Job-Baytto/06_RandD_Brain/02_Data_Imports"
    )
    print(f"\n默认输出路径: {default_output}")
    use_default = input("使用默认路径? (y/n): ").lower()

    if use_default == "y":
        output_dir = default_output
    else:
        output_dir = get_input_path("请输入输出目录路径:")

    # 5. 执行处理
    clean_directory(output_dir)

    count = 0
    print_info("开始生成 Markdown 文件...")

    for index, row in df.iterrows():
        # 提取数据
        task_name = str(row[mapping["task_name"]]).strip()

        # 安全检查：跳过空行
        if not task_name or task_name.lower() == "nan":
            continue

        status = row[mapping["status"]] if "status" in mapping else "Todo"
        start = (
            format_date(row[mapping["start_date"]])
            if "start_date" in mapping
            else datetime.now().strftime("%Y-%m-%d")
        )
        due = format_date(row[mapping["due_date"]]) if "due_date" in mapping else ""
        project = row[mapping["project"]] if "project" in mapping else "General"
        assignee = row[mapping["assignee"]] if "assignee" in mapping else "Unassigned"

        # 生成安全文件名
        safe_filename = "".join(
            [
                c
                for c in task_name
                if c.isalpha() or c.isdigit() or c in (" ", "-", "_", ".")
            ]
        ).strip()
        if not safe_filename:
            safe_filename = f"Task_{index}"

        # Markdown 内容
        md_content = f"""---
type: task
task_name: "{task_name}"
status: {status}
start_date: {start}
due_date: {due}
assignee: "{assignee}"
project: "{project}"
created_at: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
---

# {task_name}

> 自动导入自: {os.path.basename(excel_path)}

- **项目**: [[{project}]]
- **负责人**: [[{assignee}]]
- **原始状态**: {status}

"""
        # 写入文件
        out_path = os.path.join(output_dir, f"{safe_filename}.md")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(md_content)
        count += 1

    print_success(f"完成！共生成 {count} 个任务文件。")
    print_info(f"请在 Obsidian 中查看: {output_dir}")

if __name__ == "__main__":
    main()
