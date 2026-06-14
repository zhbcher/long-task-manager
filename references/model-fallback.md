# Model Fallback — 模型自动回退

> 借鉴 OMO SPM 的 model-fallback 机制。子代理调用失败时自动切换回退模型，避免人工干预。

## 核心原理

每个子代理任务有一个 `model_tier`（fast/standard/strong）。如果主模型调用失败（provider error），系统自动尝试回退链中的下一个模型，最多 3 次。

## 回退链配置

根据任务复杂度分配 tier 和 fallback chain:

| Tier | 用途 | Fallback Chain | 建议配置方式 |
|------|------|---------------|-------------|
| `fast` | boilerplate, config, 简单重构 | 轻量模型 → fallback 1 → fallback 2 | 在 WBS ledger model_tier 列或映射表中指定 |
| `standard` | 常规实现、测试 | 主力模型 → 不同 provider fallback | 同上 |
| `strong` | 架构设计、根因分析、复杂算法 | 最强模型 → fallback 1 → fallback 2 | 同上 |

**配置位置**: 在 task ledger 的 `model_tier` 列指定。模型 ID 不写死在技能中，运行时从用户配置读取。

---

## 错误识别（17 种模式）

自动检测以下错误类型，触发回退:

| 错误模式 | 描述 | 是否可重试 |
|----------|------|-----------|
| `rate_limit` | 速率限制（429） | ✅ |
| `quota_exceeded` | 配额用尽 | ✅ |
| `overloaded` | 服务过载（529） | ✅ |
| `bad_gateway` | 网关错误（502/504） | ✅ |
| `timeout` | 请求超时 | ✅ |
| `model_not_supported` | 模型不支持 | ✅ |
| `service_unavailable` | 服务暂时不可用 | ✅ |
| `connection_error` | 连接失败 | ✅ |
| `context_length_exceeded` | 上下文过长 | ⚠️ 需要压缩 |
| `invalid_api_key` | API Key 无效 | ❌ 不可重试 |
| `insufficient_balance` | 余额不足 | ❌ 需人工处理 |
| `content_policy_violation` | 内容违规 | ❌ 需人工调整 |
| `internal_error` | 内部错误 | ✅ |
| `no_error` | 空错误（静默失败） | ✅ |
| `tool_not_found` | 工具不存在 | ⚠️ 检查工具名 |
| `parse_error` | 响应解析失败 | ✅ |
| `unknown` | 未知错误 | ✅ |

**不可重试的错误 → 立即上报用户**。

---

## 自动重试流程

```
IF 子代理调用失败:
  1. 识别错误类型（从响应中提取 error.code / 消息关键词）
  2. 如果 error 在可重试列表中:
     - 查看该 model 的 retry_count（默认 0）
     - 如果 retry_count < 3 且 fallback chain 中还有模型:
       → 切换到下一个 fallback 模型
       → retry_count += 1
       → 重新 dispatch（记录新 model 和 retry_count）
     - 如果 retry_count == 3:
       → 标记任务 BLOCKED（原因: model-retry-exhausted）
       → 上报用户
  3. 如果 error 不可重试:
     → 立即上报用户（含错误详细信息）
```

**记录到 Heartbeat**:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:23 | Task 2 (standard) | - | retry 1: fallback to standard tier alternate | subagent dispatch |
| 14:24 | - | Task 2 | success on fallback | Task 3 ready |

---

## 配置示例

任务 ledger 中:

| ID | Work Package | Dependencies | Context Brief | Exit Criteria | Evidence | Status | model_tier |
|----|-------------|--------------|---------------|---------------|----------|--------|-----------|
| 2 | Implement API | 1 | Cold-start: after scaffold... | API returns 200 | curl output | todo | standard |
| 3 | Database schema | 1 | Cold-start: after scaffold... | migrations run | db:migrate output | todo | fast |

执行时:
- Task 2 → fast tier，失败则自动切 fallback 2 → fallback 3
- Task 3 → standard tier，失败则自动切 fallback 2 → fallback 3

---

## 与 SPM 其他部分的协作

- **Subagent-Driven Development**: dispatch 时传 `model_tier`，失败时自动重试
- **Ralph Loop**: 验证失败走 Ralph Loop，model fallback 仅处理 provider error
- **Todo Enforcement**: 任务最终 done 前检查 evidence，不管中间是否回退过
- **Event Store**: 记录 `subagent.dispatch` 事件时附带 `{model, retry_count, fallback_used}`

---

## 监控与告警

在 Heartbeat Log 中记录:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| HH:MM | T2 (fast tier) | T1 done | - | T2 retry |
| HH:MM | - | T2 (standard) | success | T3 dispatch |

如果同一小时内同一 tier 回退次数 > 5，触发告警（可能是 provider 配额问题）。

---

## 手动覆盖

特殊情况需要强制使用特定模型（不触发回退）:

```bash
# 在 dispatch 时显式指定 model（覆盖 tier 映射）
sessions_spawn(task="...", model="<具体模型ID>")
```

**谨慎使用**，一般只在用户明确要求时。

**提醒**: 使用前务必确认该模型 ID 在你的 OpenClaw 配置中存在（`openclaw models list`）。

---

## 铁律

- ✅ 回退自动、无感、不影响 WBS 更新
- ✅ 每次回退记录到 Heartbeat
- ✅ 3 次失败后必须上报，不再自动重试
- ✅ 不可重试的错误（invalid_key、policy violation）立即上报
- ❌ 不要隐藏回退（必须记录 fallback_used）
- ❌ 回退后不降低任务期望（仍要达到 exit criteria）
