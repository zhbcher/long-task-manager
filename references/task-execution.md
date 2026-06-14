# Task Execution — 任务执行规范

> 每个长任务执行前必须阅读本文件。这是所有执行规则的单一入口。

## 核心原则

1. **先验证后声明** — 任何完成声明必须有新鲜验证证据（本次会话执行）
2. **冷启动上下文** — 每个任务必须提供自包含的 Context Brief
3. **WBS 绑定** — 每个任务开始/结束必须更新 WBS 台账状态和证据
4. **失败先查因** — 遇到错误先查资料找原因，不盲目重试（最多3次）
5. **变更留痕迹** — 所有计划变更必须在 Mutation Log 记录

---

## 执行前自检清单

在开始任何任务前，确认：

- [ ] 已读 WBS 台账，了解任务 ID、Context Brief、Exit Criteria
- [ ] 前置依赖任务状态都是 `done`（非 `todo`/`blocked`）
- [ ] WBS 台账 `status` 已更新为 `doing`
- [ ] Heartbeat Log 已记录当前任务开始时间

---

## 任务执行流程

### 1. 准备阶段

```
1. 读取 WBS 任务行:
   - ID
   - Work Package 描述
   - Dependencies
   - Context Brief
   - Exit Criteria

2. 验证前置依赖:
   - 所有 dep ID 在 WBS 中存在
   - 所有 dep ID 状态 = done

3. 更新 WBS: status = doing
4. 记录 Heartbeat: Active = Task ID, time = now
```

### 2. 执行阶段

按照任务描述执行操作。每完成一个关键步骤：

- 记录中间结果（到临时文件或变量）
- 如果有命令输出，保存到证据包

### 3. 验证阶段（最关键）

**Gate Function — 验证门**:

```
BEFORE claiming completion:

1. IDENTIFY: 什么命令能证明这个退出标准？
   - 任务要求 "API returns correct data" → 需要 curl 命令 + 输出
   - 任务要求 "build passes" → 需要构建命令 + exit code
   - 任务要求 "file exists" → 需要 ls 命令 + 文件清单

2. RUN: 完整执行验证命令（不能使用上次的输出）
   - 必须在本会话中重新运行
   - 必须完整输出，不能截断

3. READ: 完整读取输出，检查 exit code，数失败数

4. VERIFY: 输出确实确认了退出标准吗？
   - 测试通过数 > 0
   - 无错误/警告（除非允许）
   - 文件确实存在且内容正确

5. ONLY THEN: 更新 WBS status = done, 写入证据
```

**常见失败（不要这样做）**:

| 错误做法 | 正确做法 |
|---------|---------|
| "上次跑过了" | 本次必须重新跑 |
| "应该能通过" | 必须看实际输出 |
| "看起来没问题" | 必须有 exit code 0 或具体通过数量 |
| 只写 "test passed" | 必须贴测试输出，"47/47 pass" |
| 用部分输出凑证据 | 必须完整命令输出 |

### 4. 证据记录格式

```markdown
Task 3 完成。
Evidence: `npm test`
```
47/47 pass, exit 0
```

或者：

```markdown
Task 5 完成。
Evidence: `curl -s http://localhost:3000/api/health`
```
{"status":"ok"}
```

**证据要求**:
- 包含验证命令本身
- 包含命令的实际输出（完整或关键部分）
- 包含 exit code（如果非 0 必须说明）
- 如果是文件，提供路径 + 内容摘要

### 5. 更新 WBS 台账

```markdown
| 3 | Implement JWT middleware | 2 | Cold-start: after User model... | API returns 200 with valid token | `npm test` → 8/8 pass | done |
```

并记录 Heartbeat Log:

| Time | Active | Completed | Evidence | Resume Point |
|------|--------|-----------|----------|-------------|
| 14:23 | Task 3 | - | test running | - |
| 14:25 | - | Task 3 | 8/8 pass | Task 4 待开始 |

---

## 错误处理与重试

### 第一步：查原因（必须）

遇到错误后，**先停下来查资料**，不要急着试下一个命令。

**查原因表格**:

| 错误类型 | 先查什么 | 工具/来源 |
|----------|----------|-----------|
| `SIGKILL` | 内存状态、swap、OOM 记录 | `vm_stat`, `dmesg` |
| `404/下载失败` | 正确下载链接、镜像源 | `curl -I <url>` |
| `权限 denied` | 目录权限、用户权限 | `ls -la`, `id` |
| `ModuleNotFoundError` | pip 包名、替代包 | `pip index versions` |
| `timeout` | 合理超时、分段方案 | 官方文档、`man` |
| `subprocess 失败` | stderr、依赖是否安装 | `which`, `pip list` |
| `web_fetch 失败` | URL 重定向链 | `curl -sI -L <url>` |
| `网络超时` | 连通性、DNS、代理 | `ping`, `dig`, `curl -v` |

### 第二步：查解决方案

找到原因后，再查正确解决方案：

- 官方文档
- GitHub Issues
- `--help` / `man`
- 已有技能/脚本
- `web_search`

### 第三步：汇报 + 行动

```
❌ 第 N 步失败：[步骤名称]
   - 错误：[具体错误信息]
   - 原因：[查资料后确认的根本原因]
   - 来源：[查了哪里]
   - 方案：[正确解决方案]
   - 正在执行：[具体做什么]
```

### 失败汇报阈值 — 最多 3 次

| 失败次数 | 必须做什么 |
|----------|-----------|
| 第 1 次失败 | 查原因 → 汇报 → 提出方案 → 执行 |
| 第 2 次失败 | 说明第1次为何无效 → 汇报新方案 → 执行 |
| 第 3 次失败 | **必须报告用户** → 给出当前状态 + 剩余选项 → 等待决策 |

**禁止**：
- ❌ 不查原因直接试下一个命令
- ❌ 不查文档直接猜解决方案
- ❌ 失败超过3次才报告用户
- ❌ 连续失败时不说明前一次为何无效

---

## WBS 更新规则

| 时机 | 动作 |
|------|------|
| 开始执行 | `status = doing` |
| 验证通过 | `status = done` + evidence 列填验证输出 |
| 阻塞 | `status = blocked` + 描述阻塞原因 |
| 跳过 | `status = skipped` + 注明跳过原因 |

**铁律**：WBS 台账必须与 Heartbeat Log 一致。

## Verification 与 Loop 的职责边界

| 模块 | 职责 | 不做什么 |
|------|------|---------|
| **Verification Gate** | 执行验证命令，输出 PASS / FAIL + 原因 + evidence | 不决定是否重试，不修改状态 |
| **Task Executor** | 读取 Verification 结果，决策下一步 | 不重新验证 |
| **Ralph Loop** | 消费 FAIL 结果，执行重试策略 | 不修改验证标准 |

**决策流程**:
```
Verification 输出 → FAIL + reason
    ↓
Task Executor 判断:
    ├─ 还有 retry budget? (attempt < 3)
    │   └─ 是 → 触发 Ralph Loop（切换策略）
    └─ 否 → 标记 blocked，上报用户
```

**铁律**: Verification 不控制流程，只输出事实。

---

## 完工自检清单

标记 `done` 前，逐项过：

- [ ] 退出标准全部满足（对照 WBS 逐条核对）
- [ ] 边界情况处理（null、空值、异常路径）
- [ ] 有可验证的证据（命令输出、文件路径）
- [ ] 证据是本次会话新鲜运行的
- [ ] Heartbeat Log 已更新
- [ ] WBS 台账行已更新为 `done`
- [ ] 无 console.log / TODO / 硬编码密钥（如适用）

**自检 fail → 修完再报完成。**

---

## 与 Long Task Manager 的关系

本文件是 detailed reference，`SKILL.md` 是 skill 定义和快速入口。执行长任务时：

1. 先读 `SKILL.md` 理解整体架构
2. 再读本文件了解具体执行规则
3. 遇到问题查 `references/` 其他文档
4. 具体操作流程查 `workflows/`
