# Long Task Manager

生产级长任务管理 **Agent Skill**。基于 WBS 台账驱动，配合子代理调度、质量门禁、自动重试和跨会话恢复，让 AI Agent 能可靠执行多步骤任务。

## 这是什么

Long Task Manager 不是一个后台服务或 Python 框架。它是一个**给 AI Agent 读的说明书**——Agent 加载 `SKILL.md` 后就知道如何：

- 建立一个 WBS 任务台账（一个 Markdown 表格）
- 按依赖顺序派发子代理执行任务
- 验证每个任务的完成质量
- 在失败时自动重试或上报
- 在会话中断后恢复进度

## 文件结构

```
long-task-manager/
├── SKILL.md                          # 技能主入口
├── references/
│   ├── task-execution.md             # 单任务执行规范
│   ├── plan-mutation.md              # 5 种计划突变操作
│   └── model-fallback.md             # 模型自动回退
├── workflows/
│   ├── subagent-driven-development   # 子代理调度流程
│   ├── verification-before-completion# 完成前验证门禁
│   ├── todo-enforcement.md           # 6 项硬件拦截检查
│   ├── ralph-loop.md                 # 自动重试（3 轮策略换）
│   └── preemptive-compaction.md      # 预压缩（参考，当前不适用）
├── templates/
│   ├── wbs-ledger.md                 # WBS 台账模板
│   └── verification-report.md        # 验证报告模板
└── scripts/
    ├── init-ledger.sh                # 初始化 WBS 台账
    ├── attest-ledger.sh              # SHA-256 哈希认证
    ├── verify-ledger.sh              # 验证台账完整性
    ├── generate-graph.sh             # 生成 Mermaid 依赖图
    ├── inject-wbs-context.py         # OpenClaw preToolUse hook
    └── session-recovery.py           # 会话恢复报告生成
```

## 使用场景

| 场景 | 适用 |
|------|------|
| 多步骤流水线（如视频制作） | ✅ |
| 长依赖安装（npm/pip/brew） | ✅ |
| 跨会话恢复（中断后续做） | ✅ |
| 并行任务协调 | ✅ |
| 失败需自动重试 | ✅ |
| 单文件简单修改 | ❌ (< 2 分钟不用) |

## 快速开始

### 1. 将技能注册到 OpenClaw

在 `openclaw.json` 中启用：

```json
{
  "skills": {
    "entries": {
      "long-task-manager": {
        "enabled": true
      }
    }
  }
}
```

### 2. 初始化 WBS 台账

```bash
bash scripts/init-ledger.sh "项目名"
bash scripts/attest-ledger.sh docs/spm/ledger.md
```

### 3. 执行任务

Agent 会自动按 WBS 顺序派发子代理：

```
读 WBS task → 更新 status=doing
→ sessions_spawn(task, context="isolated")
→ 等待返回 → 验证 → 更新 status=done + evidence
→ 进入下一个任务
```

### 4. 查看依赖关系

```bash
bash scripts/generate-graph.sh docs/spm/ledger.md
```

输出 Mermaid 流程图，可以粘贴到 Markdown 或 [mermaid.live](https://mermaid.live) 查看。

## 核心规则

### ⛔ Pre-Work Gate

满足任一条件即必须走 long-task-manager，不得先开工再补 WBS：

1. 涉及 ≥2 个文件修改
2. 涉及依赖安装
3. 涉及子代理调度
4. 预估 > 5 分钟
5. 需要跨会话恢复
6. 涉及失败重试或质量门禁

### ✅ Verification Gate

标记 `done` 前必须执行：

```
IDENTIFY → RUN → READ → VERIFY → ONLY THEN
```

### 🔒 Todo Enforcement

6 项检查，不通过不准推进：

- Status=done/blocked/skipped
- Evidence 非空且可验证
- Evidence 匹配 exit criteria
- 无悬空引用
- 并行任务无冲突
- 前驱任务全 done

### 🔄 Ralph Loop

验证失败自动重试，最多 3 轮，每轮换策略：

- **Strategy A**: 精准定位报错行修复
- **Strategy B**: 回滚 + 换方案
- **Strategy C**: 拆分子任务

3 轮失败 → 上报用户。

### 📝 计划突变

split / insert / skip / reorder / abandon — 全部记录 Mutation Log，不删原行。

## WBS 台账结构

| ID | Work Package | Dependencies | Context Brief | Exit Criteria | Evidence | Status |
| 7 列，done 必须有 evidence。 | | | | | | |

台账放在 `docs/spm/ledger.md`，带 Shared Context 和 Environment Prerequisites 段落。

## 环境要求

- bash 3.2+ / zsh
- macOS 或 Linux
- Python 3（仅 inject-wbs-context 和 session-recovery 脚本需要）
- OpenClaw（Agent 运行时）

## 脚本兼容性

| 脚本 | macOS | Linux |
|------|-------|-------|
| init-ledger.sh | ✅ | ✅ |
| verify-ledger.sh | ✅ | ✅ |
| attest-ledger.sh | ✅ (shasum) | ✅ (sha256sum) |
| generate-graph.sh | ✅ | ✅ |
| inject-wbs-context.py | ✅ (Python 3) | ✅ |
| session-recovery.py | ✅ (Python 3) | ✅ |

## License

MIT
