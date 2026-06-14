#!/usr/bin/env python3
"""
session-recovery.py — 从 Heartbeat Log 生成会话恢复报告

用法:
  python3 scripts/session-recovery.py [ledger_path]

输出:
  恢复报告（markdown），包括:
  - 最后完成的任务
  - 当前活跃任务
  - Resume Point（建议从哪里继续）
  - 阻塞原因（如 any blocked tasks）
"""

import sys
import re
from pathlib import Path
from datetime import datetime

def read_ledger(ledger_path="docs/spm/ledger.md"):
    with open(ledger_path, 'r', encoding='utf-8') as f:
        return f.read()

def parse_heartbeat_table(content):
    """解析 Heartbeat Log 表格，返回 entries"""
    lines = content.split('\n')
    entries = []
    in_table = False
    for line in lines:
        # 支持中英文表头：| Time | / | 时间 |
        if re.match(r'\|\s*(时间|Time)\s*\|', line.strip()):
            in_table = True
            headers = [h.strip() for h in line.split('|')][1:-1]
            continue
        if in_table:
            if not line.strip().startswith('|'):
                break
            cells = [c.strip() for c in line.split('|')][1:-1]
            if len(cells) >= 5:
                entry = dict(zip(headers, cells))
                entries.append(entry)
    return entries

def parse_wbs_tasks(content):
    """解析 WBS 任务表，返回 tasks 字典（支持中英文表头）"""
    tasks = {}
    lines = content.split('\n')
    in_table = False
    headers = []
    for line in lines:
        # 支持中英文表头：| ID | / | 任务编号 |
        if re.match(r'\|\s*(ID|任务编号|序号)\s*\|', line.strip()):
            in_table = True
            headers = [h.strip() for h in line.split('|')][1:-1]
            continue
        if in_table:
            if not line.strip().startswith('|'):
                break
            cells = [c.strip() for c in line.split('|')][1:-1]
            if len(cells) >= 7:
                task = dict(zip(headers, cells))
                task_id = task['ID']
                tasks[task_id] = task
    return tasks

def find_last_completed(entries):
    """找最近一条 Completed 非空"""
    for entry in reversed(entries):
        completed = entry.get('Completed', '').strip()
        if completed and completed != '-':
            return entry
    return None

def find_active_task(entries):
    """找最近一条 Active 非空"""
    for entry in reversed(entries):
        active = entry.get('Active', '').strip()
        if active and active != '-':
            return entry
    return None

def find_blocked_tasks(tasks):
    """找出所有 blocked 任务"""
    blocked = []
    for task_id, task in tasks.items():
        if task.get('Status', '').lower() == 'blocked':
            blocked.append({
                'id': task_id,
                'work_package': task.get('Work Package', ''),
                'reason': task.get('Evidence', '')  # evidence 列通常存放阻塞原因
            })
    return blocked

def generate_report(ledger_path):
    content = read_ledger(ledger_path)
    entries = parse_heartbeat_table(content)
    tasks = parse_wbs_tasks(content)

    if not entries:
        return "❌ No heartbeat entries found. Cannot generate recovery report."

    last_completed = find_last_completed(entries)
    active = find_active_task(entries)
    blocked_tasks = find_blocked_tasks(tasks)

    # 统计
    doing_count = sum(1 for t in tasks.values() if t.get('Status', '').lower() == 'doing')
    todo_count = sum(1 for t in tasks.values() if t.get('Status', '').lower() == 'todo')

    # 生成时间戳
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    report = f"""# Session Recovery Report

Generated: {now}
Source: {ledger_path}

## 📊 Summary

- Total tasks: {len(tasks)}
- Doing: {doing_count}
- Todo: {todo_count}
- Blocked: {len(blocked_tasks)}

## 🎯 Current Status

"""

    if active:
        report += f"""**Active Task:** {active.get('Active')}
**Started:** {active.get('Time')}
**Resume Point:** {active.get('Resume Point', '-')}

"""
    else:
        report += "No active task (all tasks idle or completed).\n\n"

    if last_completed:
        report += f"""## ✅ Last Completed

**Task:** {last_completed.get('Completed')}
**Time:** {last_completed.get('Time')}
**Evidence:** {last_completed.get('Evidence', '-')}

"""
    else:
        report += "No completed tasks yet.\n\n"

    if blocked_tasks:
        report += "## 🚫 Blocked Tasks\n\n"
        for bt in blocked_tasks:
            report += f"- **Task {bt['id']}**: {bt['work_package']}\n"
            report += f"  Reason: {bt['reason']}\n\n"
    else:
        report += "## 🟢 No Blocked Tasks\n\n"

    report += "## 📋 Recommended Next Steps\n\n"
    if doing_count > 0:
        report += "1. Continue current active task(s)\n"
    if todo_count > 0:
        report += "2. Dispatch next todo task(s)\n"
    if blocked_tasks:
        report += "3. Resolve blocked tasks:\n"
        for bt in blocked_tasks:
            report += f"   - Task {bt['id']}: {bt['reason']}\n"
    if not any([doing_count, todo_count, blocked_tasks]):
        report += "✅ All tasks completed. Project ready for delivery.\n"

    return report

def main():
    ledger_path = "docs/spm/ledger.md"
    if len(sys.argv) > 1:
        ledger_path = sys.argv[1]

    if not Path(ledger_path).exists():
        print(f"❌ Ledger not found: {ledger_path}")
        sys.exit(1)

    report = generate_report(ledger_path)
    print(report)

if __name__ == "__main__":
    main()
