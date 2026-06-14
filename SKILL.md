---
name: long-task-manager
description: "生产级长任务管理。基于 WBS 任务台账、5 种计划突变协议、子代理调度、质量门禁、自动重试、预压缩、完整审计追踪。用于依赖安装、多阶段流水线、跨会话任务管理等场景。"
---

# Long Task Manager — 长任务管理器

> 借鉴 OMO SPM 的 WBS 体系，实现生产级长任务管理：结构化台账、计划突变审计、子代理调度、质量门禁、Ralph Loop 自动重试、Model Fallback、预压缩、完整 Heartbeat 追踪。

## 核心价值

| 问题 | 本技能解决方案 |
|------|----------------|
| "我上次做到哪了？" | ✅ WBS 台账 + Active State + Heartbeat Log 精确恢复点 |
| "计划变了怎么记录？" | ✅ 5 种突变操作（split/insert/skip/reorder/abandon）+ Mutation Log |
| "子代理失败了怎么办？" | ✅ Model Fallback（自动切换）+ Ralph Loop（重试 3 轮） |
| "上下文爆了怎么办？" | ✅ WBS 台账 + Active State + Heartbeat Log 精确恢复点（使用 `/reset` 后恢复） |
| "谁动了 WBS？" | ✅ Hash Attestation（SHA-256 完整性保护） |
| "如何验证任务完成？" | ✅ Todo Enforcement 硬件拦截 + Verification Before Completion |
| "如何避免盲目试错？" | ✅ 失败先查资料 + 3 次失败阈值 + WebFetch Redirect Guard |

---

## 何时使用

- **长依赖安装**（npm/pip/brew 等需要多步、可能失败的安装）
- **跨会话任务**（需要中断后恢复的长时间工作）
- **多步骤流水线**（任务链依赖清晰，需要可追溯）
- **并行任务协调**（独立任务同时执行）
- **审计要求高**（需要完整变更记录和证据包）
- **可能失败需重试**（网络不稳定、API 限流等场景）

## 何时不用

- 单文件简单修改（< 2 分钟）
- 无需追踪的临时尝试
- 一次性的查询/搜索

---

## 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                   Long Task Manager                         │
│  Orchestrator: 统一调度子代理 + 监控 WBS + 执行 Gates     │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   WBS Ledger │  │ Heartbeat    │  │ Event Store  │
│  (Single SOT)│  │ (10min)      │  │ (Structured) │
└──────────────┘  └──────────────┘  └──────────────┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ▼
        ┌─────────────────────────────────────────────┐
        │   Execution Layer (Subagent-Driven)        │
        │  • Model Tier Routing                      │
        │  • Model Fallback (auto retry)             │
        │  • Hashline Edit Verification              │
        │  • Verification Gate (Eval Delta)          │
        │  • Ralph Loop (3 rounds auto-retry)        │
        └─────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Preemptive   │  │ Todo         │  │ Plan         │
│ Compaction   │  │ Enforcement  │  │ Mutation     │
│ (Token 预压缩)│  │ (硬件拦截)    │  │ (5 种操作)    │
└──────────────┘  └──────────────┘  └──────────────┘
```

---

## 核心组件

| 目录 | 文件 | 作用 |
|------|------|------|
| `templates/` | `wbs-ledger.md` | WBS 台账模板（7 列 + Active State + Heartbeat + Mutation Log） |
| `templates/` | `verification-report.md` | 标准化验证报告（7 阶段矩阵） |
| `references/` | `task-execution.md` | 单任务执行规范（Gate Function + 证据要求 + 错误处理） |
| `references/` | `plan-mutation.md` | 5 种计划突变操作 + 审计要求 |
| `references/` | `model-fallback.md` | 模型自动回退（17 种错误识别 + fallback chain） |
| `workflows/` | `subagent-driven-development.md` | 子代理调度流程 + 并行任务 + 审查 |
| `workflows/` | `verification-before-completion.md` | 完成前验证 + Eval Delta + 标准化报告 |
| `workflows/` | `todo-enforcement.md` | 硬件拦截（6 项检查清单） |
| `workflows/` | `preemptive-compaction.md` | Token 预压缩（3 级策略 + 恢复上下文） |
| `workflows/` | `ralph-loop.md` | Ralph Loop 自动闭环重试（3 轮策略轮换） |
| `scripts/` | `verify-ledger.sh` | 验证 WBS 完整性（依赖、循环、evidence、hash） |
| `scripts/` | `attest-ledger.sh` | 生成 SHA-256 哈希，保护 ledger 不被篡改 |
| `scripts/` | `inject-wbs-context.py` | preToolUse hook: 注入当前 WBS 上下文 |
| `scripts/` | `session-recovery.py` | 从 Heartbeat 生成恢复报告 |
| `scripts/` | `init-ledger.sh` | 初始化新的 WBS ledger |

---

## 快速开始

### 1. 初始化 WBS Ledger

```bash
cd /path/to/your/project
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/.agents/skills/long-task-manager"
bash "$SKILL_DIR/scripts/init-ledger.sh" "My Project"
# 生成: docs/spm/ledger.md

# 编辑 ledger，添加第一任务
vim docs/spm/ledger.md

# 哈希认证（保护完整性）
bash "$SKILL_DIR/scripts/attest-ledger.sh" docs/spm/ledger.md
```

### 2. 配置 OpenClaw Hook（可选但推荐）

在 `~/.openclaw/openclaw.json` 中:

```json
{
  "skills": {
    "entries": {
      "long-task-manager": {
        "enabled": true
      }
    }
  },
  "hooks": {
    "preToolUse": [
      {
        "command": "python3 .agents/skills/long-task-manager/scripts/inject-wbs-context.py",
        "maxChars": 1500
      }
    ]
  }
}
```

这样每次工具调用前，agent 都会看到当前 WBS 上下文（当前任务、最后完成、活跃任务数）。

### 3. 执行第一个任务

参考 `references/task-execution.md` 的流程:

```
1. 读 WBS → 确认任务 ID、Context Brief、Exit Criteria
2. 更新 WBS: status=doing
3. 记录 Heartbeat: Active = Task ID
4. 执行任务操作
5. 运行验证命令（fresh）
6. 读取验证输出，确认通过
7. 更新 WBS: status=done + evidence
8. 记录 Heartbeat: Completed = Task ID
9. 进入下一个任务
```

---

## 关键工作流

### 工作流 1: Subagent-Driven Development（子代理调度）

**适用**: 多任务、需隔离、预估 > 5 分钟

流程:
```
读 WBS task → 更新 status=doing → Heartbeat dispatch
→ sessions_spawn(implementer prompt)
→ 等待返回 → Heartbeat completion
→ 更新 WBS status + evidence
→ (可选) Spec Reviewer → (可选) Quality Reviewer
→ 标记完成
```

关键特性:
- Cold-Start Context Brief（自包含，不需读前置任务）
- Model Tier 路由（fast/standard/strong）
- Model Fallback 自动重试（provider error）
- 并行任务 dispatch（无依赖的任务同时派发）

文档: `workflows/subagent-driven-development.md`

---

### 工作流 2: Verification Before Completion（完成前验证）

**核心铁律**: NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE

Gate Function 5 步:
```
1. IDENTIFY: 什么命令验证？
2. RUN: 本次会话执行
3. READ: 读全部输出，check exit code
4. VERIFY: 输出确实证明了 claim？
5. ONLY THEN: 更新 WBS done
```

Eval Delta（执行前后对比）:
```
Baseline:  47 tests | 100% pass | 72% coverage
Current:   54 tests | 100% pass | 78% coverage
Delta:     +7 tests | 0 regressions | +6% coverage
```

文档: `workflows/verification-before-completion.md`

---

### 工作流 3: Todo Enforcement（硬件拦截）

**触发**: 子代理返回后、进 Phase 4 前、用户说"继续"时

**检查清单** (6 项):
```
□ WBS status = done/blocked/skipped
□ evidence 非空且可验证
□ evidence 匹配 exit criteria
□ 无悬空引用
□ 并行任务无冲突
□ 全部前驱任务 done（或 skipped）
```

**任何不通过 → 拦截，不准推进**。

文档: `workflows/todo-enforcement.md`

---

### 工作流 4: Ralph Loop（自动闭环重试）

**触发**: 验证门失败、子代理返回 `DONE_WITH_CONCERNS`

**规则**:
- 最多 3 轮
- 每轮必须换策略（A → B → C）
- 3 轮失败 → 上报用户

**策略**:
- **Strategy A**: 直接定位报错行 + 精准修复
- **Strategy B**: 回滚 + 换实现方案
- **Strategy C**: 拆分任务为更小子任务

文档: `workflows/ralph-loop.md`

---

### 工作流 5: Preemptive Compaction（预压缩）

**触发**: 上下文用量 > 60% / 每 3 轮对话 / 并行任务前

**3 级压缩**:
- **Level 1 (>60%)**: 清空已完成工具输出、合并心跳
- **Level 2 (>80%)**: 缩写子代理输出、压缩文件读取记录
- **Level 3 (>90%)**: 归档完成任务 + 启动新会话 + 写恢复点

**恢复上下文格式**:
```markdown
## Active State (Compacted at HH:MM)
- Current task: ID 3 — Core feature A
- Last completed: ID 2 — Setup scaffold
- Context window: 62% → 38%
- Resume point: File src/routes/api.ts L45-120 need modification
```

文档: `workflows/preemptive-compaction.md`

---

### 工作流 6: Model Fallback（自动回退）

**触发**: 子代理 dispatch 失败，错误类型在可重试列表

**配置**: 按 tier 分配主模型和 fallback chain（在 WBS ledger 中配置，不要在技能里写死）:

| Tier | 用途 | 建议配置方式 |
|------|------|-------------|
| fast | 简单任务（boilerplate、配置、简单重构） | 选最快返回的轻量模型，fallback 1-2 个替代 |
| standard | 常规实现、测试 | 选主力模型，fallback 一个不同 provider 的模型 |
| strong | 架构设计、根因分析、复杂算法 | 选能力最强的模型，fallback 1-2 个 |

具体模型 ID 从 WBS 台账的 `model_tier` 列或外部配置读取，**不硬编码在技能定义中**。例如 `sessions_spawn(model=task_model_mapping[tier])`。

**可重试错误** (17 种):
rate_limit, quota_exceeded, overloaded, bad_gateway, timeout, model_not_supported, service_unavailable, connection_error, internal_error, no_error, tool_not_found, parse_error, unknown...

**不可重试**:
invalid_api_key, insufficient_balance, content_policy_violation → 立即上报

文档: `references/model-fallback.md`

---

## 使用流程（完整生命周期）

```
Phase 0: Context Init（可选）
  → 如果项目全新，先做 Deep Context Initialization（扫描项目结构，生成 context-map.md）

Phase 1: Requirement（人工审批）
  → Soul-Searching Interview（3 个致命问题）
  → Brainstorming（2-3 种方案对比）
  → 输出 Design Doc 到 docs/spm/specs/
  → 用户批准设计

Phase 2: Planning（人工审批）
  → 分解 spec 为 WBS 任务（每任务 2-5 分钟）
  → 为每个任务写 Context Brief（自包含）
  → 分配 model_tier
  → 生成 WBS ledger
  → Adversarial Plan Review（可选）
  → 用户确认 WBS
  → 运行: bash scripts/attest-ledger.sh

Phase 3: Execution（自动）
  → Git Worktree 隔离
  → For each task:
     1. 更新 WBS status=doing
     2. Heartbeat: dispatch
     3. sessions_spawn(implementer)
     4. 等待返回 (sessions_yield)
     5. 更新 WBS status+evidence
     6. 审查（Spec → Quality）
     7. Heartbeat: completed
  → 并行任务：无依赖的 dispatch 多个子代理
  → Hashline Edit Verification 校验每次 edit/write
  → Todo Enforcement Gate（结束前检查所有任务 evidence）

Phase 4: Quality（自动 + 人工）
  → Verification Gate（7 阶段矩阵）
  → Eval Delta 对比 baseline/current
  → 失败 → Ralph Loop（最多 3 轮）
  → 通过 → 3 Stage Code Review
  → Comment Checker（去 AI 注释）
  → 3-Tier Quality Gates

Phase 5: Delivery（人工决策）
  → Finish Branch（merge / PR / keep / discard）
  → Deploy（可选）
  → 写 Delivery Summary
  → 更新 WBS 交付总结
```

**Tracking Layer（全程）**:
- Heartbeat Log（每完成一个子任务后更新）
- WBS Hash Attestation（每次更新 ledger 后运行 `attest-ledger.sh`）

---

## WBS Ledger 结构详解

### 7 列设计

| 列 | 说明 | 要求 |
|----|------|------|
| **ID** | 任务唯一标识（1, 2, 2.5, 3.1...） | 支持 split/insert 编号 |
| **Work Package** | 任务描述（一句话） | 清晰、可执行 |
| **Dependencies** | 前置任务 ID（逗号分隔或 -） | 必须是 WBS 中存在 ID |
| **Context Brief** | 冷启动上下文（必须自包含） | 目标 + 前置产物 + 涉及文件 + 约束 + 验收 |
| **Exit Criteria** | 退出标准（如何知道完成了） | 可验证，如 "API returns 200" |
| **Evidence** | 证据（验证命令输出） | 命令 + 输出，必须有 |
| **Status** | todo / doing / done / blocked / skipped | done 必须有 evidence |

### Context Brief 模板

```
Context Brief: [任务标题]

本任务目标: [一句话]

前置产物: [依赖任务完成了什么？如 "Task 1 已生成 src/models/user.ts"]

涉及文件:
- 新建: src/middleware/auth.ts
- 修改: src/routes/api.ts

关键约束:
- 使用 HS256 算法
- token 有效期 24h
- 密钥从 process.env.JWT_SECRET 读取

验收要点:
- POST /auth/login 返回有效 token
- GET /me 携带 token 返回用户信息
```

---

## 5 种计划突变操作

| 操作 | 触发 | 如何做 | 审计要求 |
|------|------|--------|---------|
| **split** | 任务太大（>30min/5 文件） | 原→skipped，新建 X.1/X.2 | 记录新 ID 到 Mutation Log |
| **insert** | 发现遗漏前置 | 在 N 和 N+1 之间插入 N.5 | 更新下游 Dependencies |
| **skip** | 任务不再需要 | 标记 skipped + 原因 | 更新依赖者 Dependencies |
| **reorder** | 依赖错误或发现并行机会 | 更新顺序 + Dependencies | 验证无循环依赖 |
| **abandon** | 方向错误 | 标记 skipped + "废弃：原因" | 注明替代方案，原任务保留可恢复 |

**铁律**: 所有突变必须记录，不删除原行（用 skipped 标记）。

---

## 集成到 OpenClaw

### 1. Hook 配置（自动注入 WBS 上下文）

在 `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "long-task-manager": {
      "enabled": true,
      "config": {
        "wbs_ledger_path": "docs/spm/ledger.md",
        "heartbeat_interval": "10m",
        "auto_attest": true,
        "pre_compact_thresholds": [60, 80, 90]
      }
    }
  },
  "hooks": {
    "preToolUse": [
      {
        "command": "python3 .agents/skills/long-task-manager/scripts/inject-wbs-context.py",
        "maxChars": 1500
      }
    ]
  }
}
```

### 2. 重启网关

```bash
openclaw gateway restart
```

### 3. 验证安装

```bash
# 检查脚本可执行
ls -la .agents/skills/long-task-manager/scripts/
# 运行 ledger 验证
bash .agents/skills/long-task-manager/scripts/verify-ledger.sh docs/spm/ledger.md
```

---

## 故障排除

| 问题 | 检查 |
|------|------|
| Hook 注入失败 | 检查 inject-wbs-context.py 路径是否可读 |
| WBS hash mismatch | 运行 `attest-ledger.sh` 重新生成哈希 |
| 子代理不更新 WBS | 检查子代理 prompt 是否包含 `references/task-execution.md` |
| Ralph Loop 无限循环 | 检查策略是否轮换（A→B→C），3 次后必须上报 |
| 上下文始终爆满 | 检查 preemptive-compaction 触发阈值是否太低 |

---

## 最佳实践

1. **任务粒度** — 每个任务 2-5 分钟，不超过 30 分钟
2. **Context Brief** — 必须自包含，新 agent 不需读前置任务
3. **Exit Criteria** — 必须可验证，避免 "完成"、"处理好" 等模糊词
4. **Evidence** — 每次 `done` 必有命令输出（test、build、curl 等）
5. **Heartbeat** — 每个子任务完成后更新，即使无进度也记录状态
6. **Mutation Log** — 任何计划变更（哪怕很小）都记录
7. **Hash** — 每次 WBS 重大更新后运行 `attest-ledger.sh`

---

## 完整参考

- **执行规范**: `references/task-execution.md`
- **突变协议**: `references/plan-mutation.md`
- **模型回退**: `references/model-fallback.md`
- **子代理调度**: `workflows/subagent-driven-development.md`
- **验证门禁**: `workflows/verification-before-completion.md`
- **硬件拦截**: `workflows/todo-enforcement.md`
- **自动重试**: `workflows/ralph-loop.md`
- **预压缩**: `workflows/preemptive-compaction.md`

---

## License

MIT © Long Task Manager Contributors.

---

<p align="center">
  <sub>Built with inspiration from OMO SPM · Production-ready for OpenClaw</sub>
</p>
