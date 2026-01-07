import csv
import os
import re
import sys
from datetime import datetime
from collections import defaultdict
from dateutil import parser

# ================= 配置区域 =================
# 1. 你的 CSV 文件路径 (文件名太长建议确认一下路径是否正确)
if len(sys.argv) < 2:
    print(f"❌ 错误: 请指定 CSV 文件路径。\n用法: python {os.path.basename(__file__)} <your_file.csv>")
    sys.exit(1)

CSV_FILE_PATH = sys.argv[1]

# 2. 输出文件夹名称
OUTPUT_DIR = "Obsidian_Import_Test"

# 3. 限制处理天数 (测试7天)
DAY_LIMIT = 400

# ================= 你的 Obsidian 模版 =================
TEMPLATE_HEADER = """---
tags: journal/daily/{year}
date: {date_str}
day_of_week: {day_of_week}
project: 
  - "[[Area-Journal]]"
year: {year}
---

# Daily_Log - {file_title} ({day_of_week})

## ✅ 今日目标 (Today's Goals)

```dataviewjs
// ----------------------------
// 自动获取“昨天”的日期
// 逻辑：基于文件名解析日期，如果文件名无法解析，则默认用“今天-1天”
// ----------------------------
const moment = window.moment;
let currentMoment;

// 尝试从文件名解析日期 (支持 "December 29, 2025" 或 "YYYY-MM-DD")
// 如果你的文件名是 "December 29, 2025"
if (moment(dv.current().file.name, "MMMM D, YYYY", true).isValid()) {{
    currentMoment = moment(dv.current().file.name, "MMMM D, YYYY");
}}
// 如果你的文件名是 "2025-12-29"
else if (moment(dv.current().file.name, "YYYY-MM-DD", true).isValid()) {{
    currentMoment = moment(dv.current().file.name, "YYYY-MM-DD");
}}
// 如果都解析不了，默认认为是“今天”
else {{
    currentMoment = moment(); 
}}

// 推算昨天
const yesterdayMoment = currentMoment.clone().subtract(1, 'days');

// 尝试寻找昨天的文件（兼容两种常见的命名格式）
// 优先找和你当前文件名格式一致的“昨天”
let yesterdayFile = dv.page(yesterdayMoment.format("MMMM D, YYYY")) || dv.page(yesterdayMoment.format("YYYY-MM-DD"));

if (yesterdayFile) {{
    // 读取文件内容寻找“明日计划”
    const content = await app.vault.read(app.vault.getAbstractFileByPath(yesterdayFile.file.path));
    const lines = content.split('\\n');
    let inTomorrow = false;
    let tasks = [];
    
    // 正则匹配：支持中文 "明日计划" 或 "Tomorrow's Plan"
    for (let line of lines) {{
        if (/^##\\s*➡️?\\s*(明日计划|Tomorrow's Plan)/i.test(line)) {{
            inTomorrow = true;
        }} else if (/^## /.test(line) && inTomorrow) {{
            break; // 遇到下一个标题，停止读取
        }} else if (inTomorrow && /^\\s*-\\s*\\[.\\]/.test(line)) {{
            tasks.push(line);
        }}
    }}
    
    if (tasks.length > 0) {{
        dv.header(4, "📋 来自昨天的计划：");
        dv.paragraph(tasks.join('\\n'));
    }} else {{
        dv.paragraph("✅ 昨天没有遗留的明日计划。");
    }}
}} else {{
    dv.paragraph(`ℹ️ 未找到昨天的日记: ${{yesterdayMoment.format("YYYY-MM-DD")}} (可能昨天未创建或文件名格式不同)`);
}}
```

---

## ⏳ 时间块记录 (Time Blocks)

**请使用 Templater 插入模板 TimeBlock-Insert-Templater.md**

{task_lines}

---

## 📈 今日时间分析 (Time Analysis)

```dataviewjs
// 1. 获取当前文件的所有带时间的任务
const tasks = dv.current().file.tasks.where(t => t.start && t.end);

let totalMinutes = 0;

function padTime(t) {{
  let [h, m] = t.split(":");
  return `${{h.padStart(2, '0')}}:${{m.padStart(2, '0')}}`;
}}

// 2. 准备表格数据
let rows = tasks.map(t => {{
    let startStr = padTime(t.start);
    let endStr = padTime(t.end);

    // 使用固定的日期字符串来计算时间差，避免跨日问题干扰
    let baseDate = "2000-01-01T";
    let startTime = new Date(baseDate + startStr);
    let endTime = new Date(baseDate + endStr);

    // 计算分钟数
    let duration = Math.round((endTime - startTime) / (1000 * 60));

    // 防止负数（比如跨午夜或填错），简单处理为绝对值或忽略
    if (duration < 0) duration += 24 * 60;

    totalMinutes += duration;

    // 👇👇👇 把这里原本的一行代码，换成上面那一长段 👇👇👇
    // 解析任务名称 (修复下划线导致的 em> 乱码问题)
    let taskNameStr = "-";
    if (t.task_name) {{
        if (t.task_name.path) {{
            let path = t.task_name.path;
            let displayName = path.split("/").pop().replace(/\\.md$/, "");
            let safeDisplayName = displayName.replace(/_/g, "_\\u200b");
            taskNameStr = `[[${{path}}|${{safeDisplayName}}]]`;
        }} else {{
            taskNameStr = String(t.task_name).replace(/_/g, "_\\u200b");
        }}
    }}
    // 👆👆👆 替换结束 👆👆👆

    return [
        t.text.replace(/\\(.*?::.*?\\)/g, "").trim(),
        startStr,
        endStr,
        duration + " min",        
        taskNameStr
    ];
}});

// 3. 输出表格
dv.table(["任务", "开始", "结束", "时长", "任务名称"], rows);

// 4. 输出总计
if (totalMinutes > 0) {{
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  let timeString = "";
  if (hours > 0) timeString += `${{hours}} 小时 `;
  if (minutes > 0) timeString += `${{minutes}} 分钟`;

  dv.paragraph(`**⏱️ 总耗时：${{timeString}}** (共 ${{totalMinutes}} 分钟)`);
}} else {{
    dv.paragraph("今天还没有记录时间块。");
}}
```

---

## 💡 想法与反思 (Ideas & Reflections)

---

## ➡️ 明日计划 (Tomorrow's Plan)

- [ ] 
"""

def clean_related_task(text):
    """
    清洗 Notion 的关联任务。
    例如: "PM: 周例会 (https://...)" -> "PM: 周例会"
    """
    if not text:
        return ""
    # 去掉括号里的 URL
    text = re.sub(r'\s*\(https?://.*?\)', '', text)
    # 去掉可能的换行
    text = text.strip()
    return text

def parse_notion_time(time_str):
    """
    解析 Notion 时间字符串。
    格式: "January 6, 2025 8:30 (GMT+8)"
    """
    if not time_str:
        return None, ""
    
    clean_str = re.sub(r'\s*\(GMT[+-]\d+\)', '', time_str)
    
    try:
        dt = parser.parse(clean_str)
        # 简单判断是否包含时间
        has_time = ":" in clean_str
        time_val = dt.strftime("%H:%M") if has_time else ""
        return dt, time_val
    except Exception as e:
        print(f"⚠️ 时间解析错误: {time_str} -> {e}")
        return None, ""

def main():
    if not os.path.exists(CSV_FILE_PATH):
        print(f"❌ 找不到 CSV 文件: {CSV_FILE_PATH}")
        return

    daily_tasks = defaultdict(list)
    
    # [FIX] 使用 utf-8-sig 以处理 BOM 导致的 "Untitled" 问题
    with open(CSV_FILE_PATH, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        
        # 调试：打印一下读取到的表头，确保 '01.Log_Title' 存在
        # print("CSV 表头:", reader.fieldnames) 

        for row in reader:
            start_str = row.get('02.Start_Time', '')
            if not start_str:
                continue

            dt, time_val = parse_notion_time(start_str)
            if not dt:
                continue

            end_dt, end_time_val = parse_notion_time(row.get('03.End_Time', ''))
            date_key = dt.strftime("%B %-d, %Y") # e.g. "January 6, 2025"

            # [FIX] 如果标题没读到，可能是列名不对，这里做个兜底
            title = row.get('01.Log_Title', '')
            if not title:
                # 尝试去掉 BOM 后的列名 (虽然 utf-8-sig 应该解决了，但为了保险)
                title = row.get('\ufeff01.Log_Title', 'Untitled')

            task_data = {
                'title': title,
                'start': time_val,
                'end': end_time_val,
                'related': clean_related_task(row.get('08.Related_Task', '')),
                'category': row.get('10.Category', ''),
                'status': row.get('05.Status', '')
            }
            daily_tasks[date_key].append(task_data)

    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    sorted_dates = sorted(daily_tasks.keys(), key=lambda x: parser.parse(x))
    
    print(f"🚀 准备处理前 {DAY_LIMIT} 天...")

    count = 0
    for date_str in sorted_dates:
        if count >= DAY_LIMIT:
            break
        
        tasks = daily_tasks[date_str]
        
        current_dt = parser.parse(date_str)
        year = current_dt.strftime("%Y")
        day_of_week = current_dt.strftime("%A")
        file_title = date_str 
        
        task_lines_list = []
        for t in tasks:
            # [FIX] 永远使用 [ ]，不替用户打钩
            check_box = "- [ ]"
            
            # [FIX] uuid 留空 (task_uuid:: )
            # [FIX] 如果标题是空的，打印个警告，方便排查
            if t['title'] == "Untitled" or t['title'] == "":
                 print(f"⚠️ 警告: {date_str} 有任务标题为空")

            line = f"{check_box} {t['title']} (start:: {t['start']}) (end:: {t['end']}) (task_uuid:: ) (task_name:: {t['related']})"
            task_lines_list.append(line)
        
        task_block_str = "\n".join(task_lines_list)

        final_content = TEMPLATE_HEADER.format(
            year=year,
            date_str=date_str,
            day_of_week=day_of_week,
            file_title=file_title,
            task_lines=task_block_str
        )

        filename = f"{date_str}.md"
        file_path = os.path.join(OUTPUT_DIR, filename)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(final_content)
        
        print(f"✅ 生成: {filename}")
        count += 1

    print("\n🎉 完成！请查看结果。")

if __name__ == "__main__":
    main()
