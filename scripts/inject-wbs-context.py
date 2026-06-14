#!/usr/bin/env python3
"""
inject-wbs-context.py — 在每次工具调用前，向 agent 注入 WBS 当前任务上下文

用法 (OpenClaw hook):
  preToolUse:
    command: python3 scripts/inject-wbs-context.py
    maxChars: 1500

输出格式:
  [current task info | last checkpoint | pending tasks | number of active tasks]
"""

import sys
import re
from pathlib import Path

def read_ledger(ledger_path="docs/spm/ledger.md"):
    """读取 WBS ledger 文件"""
    try:
        with open(ledger_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return None

def extract_active_state(content):
    """提取 Active State section 内容（支持中英文标题）"""
    match = re.search(r'##\s*(?:当前执行状态|Active State)[（(]?(?:Active State)?[）)]?\n(.*?)(?=##|\Z)', content, re.DOTALL)
    if match:
        return match.group(1).strip()
    return "No active state"

def extract_heartbeat_last(content):
    """提取最近一条 Heartbeat Log（支持中英文表头）"""
    # 找到 Heartbeat Log table，取最后一行
    lines = content.split('\n')
    in_table = False
    last_line = ""
    for line in lines:
        if re.match(r'\|\s*(时间|Time)\s*\|', line.strip()):
            in_table = True
            continue
        if in_table and line.strip().startswith('|'):
            # 跳过分隔行 |---|---| 和空数据行
            stripped = line.strip()
            if stripped.replace('|', '').replace('-', '').replace(' ', '').strip() == '':
                continue
            last_line = line
        elif in_table and not line.strip().startswith('|'):
            break
    if last_line:
        # 提取关键字段
        parts = [p.strip() for p in last_line.split('|')]
        if len(parts) >= 5:
            return f"Last activity: {parts[1]} | Active: {parts[2]} | Completed: {parts[3]}"
    return "No heartbeat yet"

def count_active_tasks(content):
    """统计 doing 状态的任务数（支持空格填充的表格行）"""
    doing_count = 0
    for line in content.split('\n'):
        # 匹配表格数据行: | ID | ...，ID 和管道间可能有空格
        if re.match(r'^\|\s*[0-9]+\s*\|', line):
            cells = [c.strip() for c in line.split('|')]
            # 最后一列是 status（markdown 表格行尾也有 |，所以 cells 最后一项是空字符串）
            if len(cells) >= 3:
                status = cells[-2] if cells[-1] == '' and len(cells) >= 2 else cells[-1]
                if status.lower() == 'doing':
                    doing_count += 1
    return doing_count

def extract_current_task(content):
    """从 Active State 提取当前任务（支持中英文）"""
    active_state = extract_active_state(content)
    # 找 "**当前任务**:" 或 "Current task:" 或 "Current item:"
    match = re.search(r'\*\*当前任务\*\*\s*[:：]\s*(.+)', active_state, re.IGNORECASE)
    if not match:
        match = re.search(r'Current (task|item):\s*(.+)', active_state, re.IGNORECASE)
        if match:
            return match.group(2).strip()
    if match:
        return match.group(1).strip()
    # 尝试从 Heartbeat 的 Active 列找
    heartbeat = extract_heartbeat_last(content)
    match = re.search(r'Active:\s*(.+)', heartbeat)
    if match:
        task = match.group(1).strip()
        if task and task != '-':
            return task
    return "No current task"

def main():
    ledger_path = "docs/spm/ledger.md"
    if len(sys.argv) > 1:
        ledger_path = sys.argv[1]

    content = read_ledger(ledger_path)
    if not content:
        print("WBS Context: [Ledger not found]")
        sys.exit(0)

    current = extract_current_task(content)
    heartbeat = extract_heartbeat_last(content)
    active_count = count_active_tasks(content)

    output = f"""WBS CONTEXT INJECTION:
🆔 Current Task: {current}
📊 Active Tasks: {active_count}
🕐 {heartbeat}

📋 Recent Completion & Resume Point: check Ledger.
🔗 Full WBS: docs/spm/ledger.md"""

    # Trim to maxChars if needed (simple truncate)
    max_chars = 1500
    if len(output) > max_chars:
        output = output[:max_chars-3] + "..."

    print(output)

if __name__ == "__main__":
    main()
