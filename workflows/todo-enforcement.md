# Todo Enforcement — 任务完成硬件拦截

借鉴 OMO SPM 的 todo-enforcement。在每个子代理任务返回后、进入下一阶段前，强制执行 WBS 完整性检查。不满足条件不允许推进。

## 触发时机

- 🛑 子代理任务返回后（Phase 3 结束点）
- 🛑 Phase 4（质量阶段）启动前
- 🛑 用户说「完成」「下一个」「继续」等推进指令时
- 🛑 WBS 状态变更为 `done` 时

---

## 拦截检查清单（Must-Pass Gates）

子代理返回后，主代理必须逐项检查：

```
□ 1. WBS 状态已更新
   → 该任务行 status 必须是 done / blocked / skipped 之一
   → 不能是 todo / doing（除非刚被设为 doing 但未返回）

□ 2. 有可验证的 evidence
   → evidence 列不能为空
   → evidence 必须是可追溯的（文件路径、命令输出、diff 片段）
   → "done" / "完成" 等裸文本不算 evidence

□ 3. evidence 与任务 exit criteria 匹配
   → 任务要求 "API returns correct data"
      → evidence 必须有 curl 输出或测试结果（显示 200 + 正确 payload）
   → 任务要求 "build passes"
      → evidence 必须有构建命令输出（exit 0）
   → 任务要求 "file exists"
      → evidence 必须有 ls 输出（文件存在 + 时间戳）
   → 不匹配 → 标记为 blocked，说明缺失项

□ 4. 没有悬空引用
   → 新代码的文件引用（import/require）都能解析
   → 文档中引用的路径都存在
   → 任何引用失效 → 自动修复或标记 blocked

□ 5. 并行任务无冲突（如果 dispatch 了多个并行子代理）
   → 各任务修改的文件集合无交集
   → 有冲突 → 标记冲突任务 blocked，等待人工裁决

□ 6.（仅 Phase 4 前）全部 completed 行 ≥ 全部非 skipped 行
   → 有 blocked 任务 → 不允许进 Phase 4
   → blocked 任务必须先执行 Mutation Protocol（拆分/跳过/放弃）
```

**任何一项不通过 → 拦截，不准进入下一阶段**。

---

## 拦截后的处理流程

### 情况 A: 缺 WBS 状态

**问题**: 子代理返回但未更新 WBS 行。

**自动处理**: 主代理从子代理输出中提取任务完成状态，自动补写 `status=done`，并触发告警记录到 Heartbeat（"WBS 状态自动补全，请子代理后续自行更新"）。

### 情况 B: 缺 evidence

**问题**: WBS evidence 列为空。

**处理**: 从子代理输出中提取验证信息（如 `npm test` 输出），自动填入。如果提取不到 → 要求子代理 **重新运行验证命令并返回输出**。

### 情况 C: evidence 不匹配 exit criteria

**问题**: 子代理声称完成，但提供的证据不足以证明所有退出标准。

**处理**:
1. 标记任务 `status = blocked`
2. 写入 blocked 原因："Evidence insufficient: missing [具体缺失项]"
3. 通知子代理补充验证
4. 如补充后仍不满足 → 触发 Ralph Loop

### 情况 D: 悬空引用

**问题**: 新代码引用文件不存在或路径错误。

**处理**:
- 自动修复: 如果明显是拼写错误，自动修正
- 无法自动修复 → `blocked`，要求子代理修复文件引用

### 情况 E: 有 blocked 任务未处理

**问题**: WBS 中存在 `blocked` 或 `doing` 任务，无法推进到下一阶段。

**处理**:
1. 强制执行 Mutation Protocol（`references/plan-mutation.md`）
2. 插入新任务或拆分阻塞任务
3. 更新 Dependencies
4. 重新调度阻塞任务
5. 只有所有非-skipped 任务都 done 才允许推进

---

## 用户可见提示

拦截发生时输出结构化信息，让用户清楚知道缺什么：

### 示例 1: 自动补全证据

```
✅ 任务 [ID 3] 已自动补全:

  - WBS 状态: doing → done（从子代理输出推断）
  - Evidence 提取: "npm test → 8/8 pass"
  - 验证通过，可继续。
```

### 示例 2: 证据不足

```
⚠️ 任务 [ID 3] 未通过完成检查:

  缺失项:
  - 证据为空（已从子代理输出提取）
  - 提取结果: "test passed"（缺乏数量支撑）

  请子代理重新运行完整验证命令 `npm test` 并返回输出。
```

### 示例 3: 无法推进到下一阶段

```
🚫 无法进入质量验证阶段（Phase 4）:

  阻塞项:
  - 任务 [ID 5] status=blocked (理由: API key 未配置)
  - 任务 [ID 7] status=doing (尚未完成)

  必须先解决以上阻塞项才能继续。
  建议:
    1. 任务 5 改为 skip（如果不需要）
    2. 任务 7 补全 evidence
    3. 或触发 Mutation Protocol 拆分/调整计划
```

---

## 与 Iron Laws 的关系

本 workflow 是以下铁律的执行层保障:

- **Iron Law 3**: No completion claims without fresh verification evidence
  - 强制检查 evidence 存在且与 exit criteria 匹配
- **Iron Law 5**: No WBS `done` without evidence
  - 硬件拦截任何 `status=done` 但 evidence 为空的情况

---

## Heartbeat 记录

每次 Todo Enforcement 检查都必须记录到 Heartbeat Log:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:23 | T3 | T2 | 8/8 pass | T3 subagent dispatched |
| 14:25 | - | T3 | 8/8 pass | Gate passed → Phase 4 |
| 14:26 | - | - | Gate failed: T4 missing evidence | T4 needs re-verify |

---

## 何时跳过 Todo Enforcement

**永远不跳过**。即使是简单单文件任务，也必须:
1. 更新 WBS status
2. 提供 evidence（哪怕只是 `ls -la` 输出）
3. 记录 Heartbeat

Todo Enforcement 是保证 WBS 可信度的最后一道防线。

---

## 与其他工作流的协作

| 工作流 | 协作点 |
|-------|--------|
| `verification-before-completion.md` | 提供 Gate Function 的具体验证步骤 |
| `subagent-driven-development.md` | 在子代理返回后触发本 Gate |
| `ralph-loop.md` | 验证失败不直接放行，触发 Ralph Loop 重试 |
| `preemptive-compaction.md` | 检查通过后，若上下文用量高则触发压缩 |

---

## 常见 failure 模式

| 失败模式 | 原因 | 解决 |
|---------|------|------|
| 子代理不更新 WBS | 子代理不知道要更新 | 在 prompt 中强制要求，并在 gate 自动补 |
| evidence 为空 | 子代理认为 "done" 就是完成 | 强化 Iron Law 5，要求必须带命令输出 |
| evidence 不匹配 exit criteria | exit criteria 描述模糊或子代理误解 | 精化 exit criteria 为可验证的形式 |
| 悬空引用 | 子代理修改了文件但未 commit 或路径错 | 要求子代理执行前先 ls 确认路径 |

---

## 检查清单（主代理使用）

执行 Todo Enforcement 前，逐项核对:

- [ ] WBS 该任务行 status 是 done/blocked/skipped 之一
- [ ] evidence 列非空且格式正确（命令 + 输出）
- [ ] evidence 内容确实证明 exit criteria（逐条对照）
- [ ] 没有悬空文件引用（import/require 都能解析）
- [ ] 并行任务无文件冲突（diff 无重叠）
- [ ] 所有前驱任务都已 done（或 skipped）
- [ ] Heartbeat Log 已更新

**任何一项不满足 → 拦截，不推进**。
