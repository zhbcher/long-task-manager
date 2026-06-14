# Verification Before Completion — 完成前验证

## 核心铁律

**NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE**

如果你没有在**本次会话**中运行验证命令，就不能 claim 任务完成。

---

## Gate Function（验证门）

任何任务标记 `done` 前，必须执行以下 5 步:

```
1. IDENTIFY: 什么命令能证明这个 claim？
   - "tests pass" → `npm test`
   - "build succeeds" → `npm run build`
   - "API returns correct data" → `curl <url>`
   - "file exists" → `ls -la <path>`

2. RUN: 完整执行该命令（不能使用上一次的输出）
   - 必须实时运行
   - 必须显示完整输出
   - 必须检查 exit code

3. READ: 读取全部输出，数失败数，确认 exit code

4. VERIFY: 输出确实支持你的 claim 吗？
   - 测试通过数 > 0 且无失败
   - 构建 exit code = 0
   - API 返回预期数据（JSON 可解析、字段存在）
   - 文件确实存在且内容正确

5. ONLY THEN: 做出声明并更新 WBS
```

**跳过任何一步 = 撒谎，不是验证**。

---

## 常见反模式

| 反模式 | 为什么错 | 正确做法 |
|-------|---------|---------|
| "上次跑过了" | 上次不是本次会话，无效 | 本次必须重新跑 |
| "应该能通过" | 假设不是证据 | 运行命令看实际输出 |
| "看起来没问题" | 视觉检查不算验证 | 需要 exit code 或数量统计 |
| 只写 "test passed" | 无数据支撑 | 必须贴输出，"47/47 pass" |
| 测试第一次就通过 | 可能测的是已有功能 | 确保测试针对新代码（RED-GREEN 流程） |
| 拿 baseline 时期输出凑数 | 基线不是本次 | 基线用于对比，不是验证 |

---

## 验证证据格式

```markdown
Task 2: Implement JWT middleware — DONE

Verification: `npm test`
```
Result: 8/8 tests passed, exit 0
Coverage: 85% (new code: 90%)
```

或者:

```markdown
Task 5: Build Docker image — DONE

Verification: `docker build -t myapp .`
```
Sending build context... done
Step 1/5 : FROM node:18-alpine
...
Successfully tagged myapp:latest
```

**证据必须包含**:
1. 验证命令本身（可选但推荐）
2. 命令的实际输出（关键部分）
3. 明确的成功指标（pass 数、exit 0、状态码）
4. 如果是文件存在，提供 `ls` 输出或 `file` 内容

---

## Eval Delta — 执行前后对比 🆕

每个任务完成后、标记 `done` 之前，必须做 **Eval Delta**（评估差异对比）:

### 执行步骤

```bash
# 1. BASELINE（执行前）
npm test 2>&1 | tee /tmp/baseline-<task-id>.log
# 记录: 总测试数、通过数、覆盖率

# 2. CURRENT（执行后）
npm test 2>&1 | tee /tmp/current-<task-id>.log

# 3. DELTA（对比）
echo "📊 Eval Delta — Task [ID]"
echo "Baseline:  $(grep -c '✓' /tmp/baseline-*.log) tests | $(cat coverage-before) coverage"
echo "Current:   $(grep -c '✓' /tmp/current-*.log) tests | $(cat coverage-after) coverage"
echo "──────────────────────────────────"
echo "Delta:     +$((current-baseline)) tests | $regressions regressions | +$((coverage-current - coverage-before))% coverage"
```

### 输出模板

```
📊 Eval Delta — Task 3

Baseline:  47 tests | 100% pass | 72% coverage
Current:   54 tests | 100% pass | 78% coverage
──────────────────────────────────
Delta:     +7 tests | 0 regressions | +6% coverage

✅ 正向变化：无回归，覆盖率和测试数均有提升
```

### 异常情况处理

| 情况 | 处理 |
|------|------|
| 覆盖率为 0（baseline 时项目无测试） | 标记为 ⚠️ 高风险（无基线），evidence 中注明 |
| 回归 > 0 | **STOP**。标记 `blocked`，进入 Ralph Loop 重试 |
| 测试数减少 | 确认是否是移除了冗余测试（合理）还是删除了有效测试（违规） |
| 覆盖率下降但无回归 | 标记为 `DONE_WITH_CONCERNS`，evidence 中注明原因 |

**铁律**: 没有 Eval Delta 对比，不能标记任务 `done`。

---

## 标准化验证报告 🆕

Phase 4 质量阶段结束时，必须使用**标准化模板**输出验证报告，禁止叙述式文字。

模板: `templates/verification-report.md`

**7 阶段顺序验证**:
1. Build
2. Types
3. Lint
4. Tests
5. Coverage
6. Security
7. Diff

**整体判定**:
- 全 PASS → ✅ **READY**
- Coverage < 80% 或其他小问题 → ⚠️ **CONDITIONAL**（可交付但需记录）
- Build/Types/Tests 任一 FAIL → ❌ **NOT READY**（禁止交付）

报告保存到 `docs/spm/reviews/YYYY-MM-DD-verification.md`，并在 WBS 台账的 evidence 列引用。

---

## Heartbeat 记录

长验证（全量测试、构建、类型检查）需要 Heartbeat:

| 时间 | 活跃任务 | 已完成 | 证据 | 恢复点 |
|------|---------|--------|------|--------|
| 14:23 | Task 2 | - | npm test running (30s expected) | - |
| 14:25 | - | Task 2 | 47/47 pass, coverage 85% | Task 3 dispatch |

**规则**:
- 验证开始 → 记录 Active + 预期时长
- 验证完成 → 记录 Completed + 证据
- 验证 > 5min → 每 2min 更新一次进度（如 "test 60% done"）

---

## 与 WBS 的协作

WBS 台账是任务完成的**唯一事实来源**。所有验证证据**必须**在任务完成时写入 WBS 的 `Evidence` 列。

```markdown
| 2 | Implement JWT middleware | 1 | Cold-start: after User model... | API returns 200 with valid token | `npm test` → 8/8 pass | done |
```

**证据要求**:
- 与 Exit Criteria 直接匹配
- 可追溯（命令可重现）
- 明确的结果（pass/fail、exit code、计数）

**禁止**: "works", "done", "tested" 等无数据支撑的文字。

---

## 与 Iron Law 3 的关系

> Iron Law 3: No completion claims without fresh verification evidence.

本 workflow 是 Iron Law 3 的详细执行层。所有子代理、inline 执行都必须遵循本流程。

---

## 常见任务验证命令

| 任务类型 | 验证命令 | 预期输出 |
|---------|---------|---------|
| API 实现 | `curl -s <url>` | HTTP 200 + JSON 响应 |
| 数据库迁移 | `npm run migrate:status` | "All migrations applied" |
| 单元测试 | `npm test -- <pattern>` | "PASS __ tests" |
| 集成测试 | `npm run test:integration` | "All integration tests passed" |
| 构建 | `npm run build` | exit 0, 无错误 |
| 类型检查 | `npm run type-check` | exit 0, "No errors" |
| 代码规范 | `npm run lint` | exit 0, "0 errors" |
| 安全扫描 | `npm run audit` | "0 vulnerabilities" |
| 文件生成 | `ls -la <path>` | 文件存在且时间戳更新 |

**原则**: 验证命令必须能由机器判断成功/失败，不能是主观感受。
