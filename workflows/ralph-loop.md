# Ralph Loop — 任务自动闭环重试

> 借鉴 OMO SPM 的 Ralph Loop 机制。任务验证失败时自动重试，不到 100% 完成不停止。

## 触发条件

- Phase 4 验证门任一检查项失败（Build/Types/Lint/Tests/Coverage/Security/Diff）
- 子代理返回 `DONE_WITH_CONCERNS`
- WBS 任务 `status=done` 但 evidence 显示有 regression

---

## 核心规则

**最多循环 3 轮。** 3 轮后仍失败 → 上报用户决策，不无限循环。

**每轮必须改变策略。** 不能盲目重试同样的操作。

---

## 执行流程

```
FOR each failed task (max 3 rounds):
  1. 读取失败原因（测试输出 / lint 报错 / 编译错误）
  2. 选择修复策略（不可与上一轮相同）:
     - Strategy A: 直接定位报错行 + 精准修复
     - Strategy B: 回滚本次改动 + 换实现方案
     - Strategy C: 拆分任务为更小子任务
  3. 派发修复子代理（含失败上下文 + 选定策略）
  4. 子代理完成后重新验证（verification-before-completion）
  5. 验证通过 → 标记 done + evidence → 退出循环
  6. 验证仍失败 → 轮次+1 → 回到步骤 1

IF 3 轮后仍失败:
  → 暂停，整理「失败根因 + 已尝试策略 + 建议」
  → 请求用户决策
```

---

## 策略选择指南

| 失败类型 | 推荐策略 | 说明 |
|---------|---------|------|
| 编译/语法错误 | Strategy A | 直接定位报错行，精准修复 |
| 测试失败（单一） | Strategy A | 修代码，让该测试通过 |
| 测试失败（多个） | Strategy C | 可能要大改，拆分成小任务 |
| 覆盖率不足 | Strategy B | 回滚到上一版本，换测试策略 |
| 多个不相关文件冲突 | Strategy B | 回滚 + 换实现方案 |
| 外部依赖/环境问题 | **不进入循环** | 立即上报用户，非代码问题 |
| 架构性错误（3次以上都暴露新问题）| **不进入循环** | 上报用户，方案需重设计 |

---

## 记录到 Mutation Log

每轮 Ralph Loop 尝试都是一次 mutation，必须记录:

| Time | Mutation Type | Affected IDs | Reason | New IDs |
|------|--------------|-------------|--------|---------|
| 14:23 | ralph-retry-1 | 3 | Test failed: expected 200 got 500 | 3 (retry with Strategy A) |
| 14:28 | ralph-retry-2 | 3 | Still failing: assertion mismatch | 3 (retry with Strategy C, split) |
| 14:35 | ralph-resolved | 3 | Split into 3.1 + 3.2, both pass | 3.1, 3.2 |

**Mutation Type 可选值**:
- `ralph-retry-1` / `ralph-retry-2` / `ralph-retry-3`
- `ralph-resolved` — 成功解决
- `ralph-escalated` — 3 次失败上报用户

---

## 子代理 Prompt 增强

修复子代理的 prompt 必须包含:

```
## Previous Attempt
{原始任务描述}

## Failure Analysis
{失败原因、错误输出、定位到的代码行}

## Chosen Strategy
{Strategy A/B/C 及理由}

## Constraints
- 不得引入新的 regressions
- 必须通过 exit criteria 验证
- 保留原有功能
```

---

## 与 Verification Gate 的关系

Ralph Loop **替代**了 Phase 4 中「验证失败 → 人工决策」的手动环节。

**标准流程**:
```
Task complete → Verification Gate → PASS → Next task
                               → FAIL → Ralph Loop (max 3 rounds)
                                   → 仍 FAIL → Escalate to user
```

**不改变 TDD 流程** — Ralph Loop 只处理 TDD 验证失败后的自动修复，不替代 TDD。

---

## 铁律

- ✅ 每轮策略必须不同（A → B → C 或包含 split）
- ✅ 3 次上限严格控制
- ✅ 每次重试必须重新验证（不能假设修好了）
- ✅ 所有尝试记录到 Mutation Log
- ✅ 3 次失败后立即上报，不继续盲目尝试
- ❌ 不要用同一策略重复尝试
- ❌ 不要隐藏失败的尝试（必须记录在案）
- ❌ 不要无限循环

---

## 示例场景

### 场景 1: 测试失败（Strategy A）

```
Task 3: 实现用户登录 API

第一次尝试:
- 运行 npm test → 3/4 tests passed
- 失败测试: POST /login returns 401 for valid credentials
- 证据: test output showing assertion failure

→ Ralph Loop (round 1):
  策略 A: 直接定位 login 函数第 27 行，发现密码比对逻辑反了
  修复: 修正条件
  验证: npm test → 4/4 pass
  ✅ 解决，记录 ralph-retry-1
```

### 场景 2: 多个失败（Strategy C）

```
Task 5: 重构认证模块

第一次尝试:
- 运行 npm test → 12/18 passed, 6 failures
- 涉及多个文件，修改影响面大

→ Ralph Loop (round 1):
  策略 C: 拆分为 5.1 (Token 生成) + 5.2 (Middleware) + 5.3 (Routes)
  记录 split mutation
  验证各子任务全部通过
  ✅ 解决
```

### 场景 3: 3 次失败上报

```
Task 7: 优化数据库查询

Round 1 (Strategy A): 索引方案 → 部分测试还是慢
Round 2 (Strategy B): 换缓存方案 → 引入数据不一致
Round 3 (Strategy C): 拆分异步加载 → 复杂度失控

3 次都失败 → 上报用户:
  "已尝试 A/B/C 三个策略均失败。根因: 该查询需要跨表 join，单纯索引/缓存/异步都难以解决。
  建议: 1) 重构数据模型 2) 接受当前性能 3) 用物化视图。请决定下一步。"
```

---

## 与 Model Fallback 的区分

| Ralph Loop | Model Fallback |
|-----------|----------------|
| 处理 **验证失败**（测试/构建/逻辑错误） | 处理 **provider error**（rate_limit/timeout/overloaded） |
| 重试时可能换实现方案（Strategy B/C） | 重试只换模型，不换代码 |
| 最多 3 轮后上报 | 最多 3 次后上报 |
| 触发条件: verification gate fail | 触发条件: subagent dispatch fail |

两者不冲突 — 子代理 dispatch 失败走 Model Fallback，子代理完成但验证失败走 Ralph Loop。

---

## 检查清单

每次 Ralph Loop 循环:

- [ ] 已读取失败原因（具体错误输出）
- [ ] 已选择新策略（与上一轮不同）
- [ ] 已构建修复 prompt（含失败上下文 + 策略说明）
- [ ] 已派发修复子代理
- [ ] 修复完成后已重新验证（完整 verification-before-completion）
- [ ] 已记录 Mutation Log（round + reason + strategy）
- [ ] 如果解决，已更新 WBS status = done
- [ ] 如果 3 次失败，已整理上报材料

---

## 与 long-task-manager 的关系

Ralph Loop 是 `long-task-manager` 的 **Phase 4 质量阶段** 标准流程，用于自动闭环验证失败的任务，减少人工干预。

在 `long-task-manager` 中引用时，应说明:

```
Phase 4: Quality
  → 使用 Ralph Loop 自动重试（最多 3 轮）
  → 3 轮失败上报用户决策
```

---

## 降级方案

如果环境中没有 subagent dispatch 能力（单会话模式），Ralph Loop 退化为:

```
手动分析失败原因 → 选择策略 → 手动修复 → 手动验证
```

仍然遵循 3 次上限和策略轮换原则。
