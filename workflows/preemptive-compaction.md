# Preemptive Compaction — 上下文预压缩（当前不适用）

> ⚠️ **当前不适用**: 本工作流描述的压缩操作（清除工具调用输出、缩写子代理输出等）依赖 Agent 直接操作会话上下文的能力，但当前 OpenClaw Agent 没有这个权限。
>
> 实际上下文管理由 OpenClaw 内置的 compaction 机制处理（配置：`compaction.keepRecentTokens: 50000`）。如果遇到上下文爆满的问题，应优先使用 `/reset` 重新开始，WBS 台账会保证恢复点不丢失。
>
> 本文件保留作为参考，但不应该在实际执行中触发。

> 借鉴 OMO SPM。长会话自动监控上下文窗口用量，逼近上限时主动压缩，防止 OOM 或截断。

## 触发条件

- 每个子代理任务完成后检查
- 每 3 轮对话后自检
- 执行并行任务前（预计上下文增长快）
- 用户说「继续」「下一个」且过去 10 分钟未检查

---

## Token 预算追踪

### 估算公式

```
tokens_used ≈ total_chars / 3.5
usage_pct = tokens_used / model_context_window * 100
```

### 常见模型上下文窗口

| 模型 | 上下文窗口 |
|------|-----------|
| DeepSeek V4 | 200K |
| Qwen 3.6 | 262K |
| MiniMax M2.7 | 200K |
| GPT-5.x | 200K |
| Step-3.5 | 128K |

> 每次切换模型时，重新读取当前模型的真实窗口大小（`session_status` 或 provider 配置）。

### Heartbeat 记录格式

| Time | Tokens Est. | Usage % | Trigger |
|------|------------|---------|---------|
| 14:23 | ~45K / 200K | 22% | - |
| 14:35 | ~95K / 200K | 47% | - |
| 14:42 | ~135K / 200K | 67% | ⚠️ Level 1 |
| 14:50 | ~170K / 200K | 85% | 🔴 Level 2 |

---

## 压缩策略

### Level 1: 轻度压缩（用量 > 60%）

操作:
- 清除已完成的工具调用输出（保留错误输出）
- 移除重复的 WBS 状态片段（只保留最新一条）
- 精简 heartbeat 日志（合并连续无变化条目）

预期压缩比: 10-20%

### Level 2: 中度压缩（用量 > 80%）

操作:
- 缩写已完成的子代理输出（只保留结论 + evidence，删除中间思考）
- 移除已解决的中间讨论（保留最终决策）
- 压缩文件读取记录（只记录文件名+行数，不保留全文）

预期压缩比: 20-30%

### Level 3: 重度压缩（用量 > 90%）

操作:
- 将所有已完成任务归档为 3 行摘要（任务ID + 结果 + 证据链接）
- 启动新的子会话继续未完成任务（sessions_spawn + sessions_yield）
- 在 WBS 中写入完整的恢复上下文（Cold-Start Context Brief + Resume Point）

预期压缩比: 40-60%

---

## 执行流程

```
每个检查点:
  1. 估算当前上下文用量（字符数 / 3.5）
  2. 对照当前模型的上下文窗口
  3. 选择压缩等级（>60% Level 1, >80% Level 2, >90% Level 3）
  4. 执行对应压缩操作
  5. 重新估算用量
  6. 更新 WBS Active State（确保中断后可恢复）
  7. 记录 Heartbeat（压缩前后对比）
```

**压缩后评估**:
- 用量 < 50% → 继续
- 用量 50-70% → 警告，但可继续
- 用量 > 70% → 优先完成当前任务 → 归档 → 启动新会话

---

## WBS Active State 恢复上下文格式

压缩后必须在 WBS 中写入:

```markdown
## Active State (Compacted at HH:MM)
- Current task: ID 3 — Core feature A
- Last completed: ID 2 — Setup scaffold (npm test passed)
- Session resumed from: 2026-06-12 14:30
- Context window: 62% → 38% after compaction
- Resume point: File src/routes/api.ts L45-120 need modification
- Pending decisions: None
```

---

## 压缩内容清单（不压缩的内容）

| 压缩项 | 内容 |
|-------|------|
| ✅ 可压缩 | 已完成子代理输出（除非含 critical evidence） |
| ✅ 可压缩 | 重复的 WBS 快照 |
| ✅ 可压缩 | 心跳日志（合并连续条目） |
| ✅ 可压缩 | 文件读取记录（全文 → 文件名/大小） |
| ❌ 不压缩 | Iron Laws（5 条永远保留） |
| ❌ 不压缩 | 用户明确指示/偏好/否决 |
| ❌ 不压缩 | 当前任务的 Context Brief 和 exit criteria |
| ❌ 不压缩 | 验证证据（test output, diff 等） |

---

## 与 Heartbeat 的协同

每次压缩操作记录到 Heartbeat:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:42 | T3 | T2 | Compacted (Level 2) | WBS Active State updated |
| 14:50 | - | T3 | Completed post-compaction | T4 dispatch |

---

## 启动新会话的迁移

Level 3 压缩时，必须启动新会话继续未完成任务:

```bash
# 1. 记录当前会话的完整 Resume Point 到 WBS Active State
echo "Resume: sessions_spawn(task='...', model='...', resume_session='$CURRENT_SESSION')" >> WBS.md

# 2. 启动新会话（主代理 reads WBS Active State 恢复上下文）
sessions_spawn(task="Continue from Task 3")
```

新会话在启动时读取 WBS 的 Active State，获得完整恢复点。

---

## 铁律

- ✅ 压缩前必须备份完整状态到 WBS Active State
- ✅ 证据不丢失（测试输出、diff 保持可访问）
- ✅ 用户可见的决策不压缩
- ✅ Iron Laws 完整保留
- ✅ 每次压缩记录压缩等级和压缩比
- ❌ 不要压缩当前任务的 Context Brief
- ❌ 不要压缩未验证的证据

---

## 监控告警

如果单次会话压缩次数 > 3（说明上下文管理有问题），记录警告到 Heartbeat 并在交付总结中标记为"高风险"。

---

## 检查清单

执行 Preemptive Compaction 前确认:

- [ ] 估算当前 token 用量
- [ ] 对照模型窗口选择正确等级
- [ ] 备份 Active State 到 WBS
- [ ] 执行压缩操作
- [ ] 验证压缩后用量 < 阈值
- [ ] 记录 Heartbeat（压缩前/后用量）
- [ ] 如果 Level 3，已启动新会话并传递 Resume Point

---

## 与 Tracking Layer 的关系

本 workflow 是 Tracking Layer 的核心组件之一，与 Heartbeat、Session Recovery 协同工作，确保长会话不崩溃、可恢复。
