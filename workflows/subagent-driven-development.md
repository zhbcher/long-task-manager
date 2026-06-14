# Subagent-Driven Development — 子代理驱动开发

## 概述

每个 WBS 任务派发一个独立的子代理（fresh subagent），执行完毕后返回。适用于多任务、需要隔离环境、或任务可能长时间运行的场景。

**核心规则**:
- 每个子代理获得任务的完整 Context Brief（冷启动）
- 子代理执行期间主代理定期心跳
- 子代理返回后必须更新 WBS 状态和证据
- BLOCKED 任务触发 Mutation Protocol

---

## 执行流程

```
FOR each task in WBS ledger (in dependency order):
  1. 读取任务: ID, Context Brief, exit_criteria, model_tier (可选)
  2. 更新 WBS: status = doing
  3. 记录 Heartbeat: Active = Task ID, 开始时间
  4. 构建 dispatch prompt:
     - Context Brief（前置产物、涉及文件、约束、验收）
     - 完整任务描述
     - Exit Criteria（精确判定标准）
     - Model Tier（用于 routing）
  5. Dispatch 子代理:
     sessions_spawn(
       task=prompt,
       model=get_model_for_tier(model_tier),  # 可选，默认用当前模型
     )
     # 不传 context 参数 = isolated（clean session）
     # 子代理有完整 Context Brief 冷启动，不需要父会话历史
  6. 等待返回:
     - 正常返回 → 继续
     - 超时（>5min 无输出）→ Heartbeat 记录等待，继续等待
     - 空返回或仅 error → 触发 empty-response 检测
  7. 子代理返回状态:
     - DONE → 继续步骤 8
     - DONE_WITH_CONCERNS → 标记证据，仍需验证
     - BLOCKED → 触发 Mutation Protocol（split/insert/skip）
  8. 记录 Heartbeat: Completed = Task ID, Evidence = 提取的输出
  9. 更新 WBS:
     - status = done / blocked / skipped
     - evidence 列填入验证输出或阻塞原因
  10. (可选) 触发 Spec Compliance Review
  11. (可选) 触发 Code Quality Review
  12. 记录 Heartbeat: Resume Point = 下一任务
```

---

## Model Routing 与 Fallback

```python
def get_model_for_tier(tier: str, mappings: dict = None) -> str:
    """
    根据 tier 返回模型 ID。mappings 从 WBS 台账或外部配置读取，
    不要在技能中硬编码特定模型。
    """
    if mappings is None:
        mappings = {
            "fast": None,       # 由调用方在 WBS ledger 的 model_tier 列中指定
            "standard": None,
            "strong": None,
        }
    return mappings.get(tier, None)
```

**自动 Fallback**（参考 `references/model-fallback.md`）:
- 检测到可重试错误（rate_limit, timeout, overloaded...）→ 自动切换 fallback chain
- 记录 retry count（max 3）
- 3 次失败后标记 `blocked` 上报

---

## Heartbeat 记录要求

**子代理 dispatch 时**:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:23 | Task 2 (standard) | Task 1 | test passed | Task 2 subagent |

**子代理返回时**:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:35 | - | Task 2 | 8/8 pass | Task 3 dispatch |

**超时等待**（dispatch 后 > 5min 无返回）:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:23 | Task 2 (standard) | - | waiting for subagent | - |
| 14:28 | Task 2 (standard) | - | still running (5min) | - |

---

## 空响应检测（借鉴 OMO）

如果子代理返回完全空内容或仅含 `error` 字段:

1. 检查 Heartbeat 确认是否真的静默失败
2. 触发 Model Fallback（换模型重试）
3. 重试最多 2 次
4. 仍空返回 → 标记 `blocked`（reason: silent_failure）

---

## 并行任务调度（Dispatch Parallel Agents）

**条件**: 任务间无文件共享、无依赖链交叉。

```
# 识别可并行任务
independent_tasks = filter tasks where:
  - 无互斥依赖
  - 涉及文件集合无交集
  - 模型 tier 不冲突（避免同一 provider 超额）

# 并行 dispatch
for task in independent_tasks:
  update WBS: status = doing
  heartbeat: log dispatch
  sessions_spawn(task=prompt, model=get_model_for_tier(task.model_tier))

# 等待全部完成
sessions_yield for each dispatched subagent

# 处理返回
for result in results:
  update WBS: status + evidence
  if BLOCKED: 触发 Mutation Protocol

# 验证无冲突
verify no file conflicts among parallel results
```

---

## 子代理 Prompt 模板

基础模板（见 `subagents/implementer-prompt.md`）结构:

```
## Context Brief（冷启动）

{task.context_brief}

---

## Task Description

{task.description}

## Exit Criteria

{task.exit_criteria}

## Constraints

{task.constraints}

## Model Tier

{task.model_tier}
```

**Context Brief 必须自包含** — 子代理不需要读任何其他任务的文件或上下文即可执行。

---

## 审查流程（Spec + Quality）

子代理完成后，按顺序触发两个审查子代理（standard tier）:

```
1. Spec Compliance Reviewer:
   - 代码是否与 spec 一致
   - 无 YAGNI 功能
   - 所有验收要点满足

   Issues? → 返回子代理修复 → 重新审查

2. Code Quality Reviewer:
   - 代码整洁度
   - 测试覆盖率
   - 安全性
   - 设计合理性

   Issues? → 返回子代理修复 → 重新审查
```

审查结果记录到 WBS 的 evidence 或备注。

---

## BLOCKED 处理

子代理返回 `BLOCKED` 时:

1. 读取阻塞原因
2. 对照 `references/plan-mutation.md` 选择合适的突变类型:
   - 任务太大 → split
   - 缺少前置 → insert
   - 不再需要 → skip
   - 方向错误 → abandon
3. 记录 Mutation Log
4. 如果大突变（split/insert/abandon）→ 触发重新审查
5. 更新 WBS 状态和 evidence

---

## 与长任务管理的关系

本 workflow 是 `long-task-manager` 的 **Phase 3 执行** 标准流程。当任务需要 multi-step、需要隔离环境、或预估运行时间 > 5 分钟时使用。

**不适用场景**:
- 单文件简单修改
- 任务 < 2 分钟
- 需要高度交互（应使用 inline）

---

## 关键检查清单

子代理 dispatch 前:
- [ ] WBS status 已设为 `doing`
- [ ] Heartbeat 已记录 Active
- [ ] Context Brief 完整且自包含
- [ ] model_tier 已指定

子代理返回后:
- [ ] WBS status 已更新（done/blocked/skipped）
- [ ] Evidence 已填入（必须是与 exit criteria 匹配的验证输出）
- [ ] Heartbeat 已记录 Completed
- [ ] 如果 BLOCKED，Mutation Log 已更新
- [ ] 审查（如启用）已完成

任何一步缺失 → 标记完成为 `DONE_WITH_CONCERNS`，要求补全。
