# hitl-dev-loop

**面向 Claude Code + 编码 Agent（默认 Codex CLI）的人机协作（Human-in-the-Loop）开发循环。**

Claude 担任主 Agent：理解需求、调研、拆解任务，把编码派给在独立 git worktree 中运行的编码 Agent，审查改动、集成、构建，然后提醒你验收。你只需要体验真实的软件，用大白话或截图反馈，并决定产品方向和发布。

v0.2 起，**可靠性由调度脚本保证，而不是靠提示词**：任务有持久化状态和锁；反馈送达有确认；「完成」由调度器独立判定并验证；集成和构建都有绑定到 commit SHA 的门禁；每一步都有超时、熔断和预算。

这不是无人监督的自动编程，而是一个把你的反馈不断变成「已验证的改动」、同时由你掌握方向的开发循环。

## 包含什么

| 路径 | 说明 |
|---|---|
| `skills/hitl-dev-loop/SKILL.md` | Claude 遵循的流程：首次接入、需求分析、派发、审查、集成、授权边界、任务队列、Token 管理。 |
| `skills/hitl-dev-loop/scripts/` | 调度脚本（兼容 macOS 自带的 bash 3.2），见下表。 |
| `skills/hitl-dev-loop/scripts/adapters/codex.sh` | Codex CLI 适配器（`exec --json --output-schema`）。实现同样的接口即可接入其他编码 Agent。 |
| `skills/hitl-dev-loop/templates/` | `AGENTS.md`、`CLAUDE.md`、`TASKS.md`、`DECISIONS.md`、共用规则、任务说明模板、报告 JSON Schema。 |
| `agents/repo-maintainer.md` | 低成本、只读的子 Agent：整理 GitHub Issue / PR，汇报需要决策的事项。 |
| `PROTOCOL.md` | 与具体工具无关的协议：角色、产物、报告格式、状态机、完成规则、门禁、适配器接口。 |
| `tests/` | 用模拟 Codex 的自动化测试（21 个场景），CI 在 ubuntu 和 macOS 上运行。 |

## 工作原理

```
你提需求/反馈 ──▶ Claude 分析、写任务说明 ──▶ dispatch.sh
                                              │
          ┌───────────────────────────────────┘
          ▼
   drive.sh（调度器）每一轮：
     送达反馈(pending→inflight) → 运行 Agent（超时/熔断/预算）
     → 读取结构化报告 → 报告 done？
         ├─ 没有真实改动 / 超出范围 → 反馈给 Agent，继续
         └─ 调度器提交 → 运行 AGENT_VERIFY_CMD（绑定 SHA）
               ├─ 失败 → 日志反馈给 Agent，继续（有上限）
               └─ 通过 → verified
          │
          ▼
   Claude 审查 diff → review.sh approve（绑定 SHA）
          ▼
   integrate.sh：在专用集成 worktree 合并 → 再验证 → 失败自动回滚
          ▼
   ship.sh：只构建已验证的集成 SHA → alert.sh 叫你验收
```

### 脚本一览

| 脚本 | 作用 |
|---|---|
| `init.sh` | 每个仓库运行一次（可重复运行）：创建 `.agent-loop/`、共用规则、集成分支，检查 Agent 是否可用。 |
| `new-task.sh <名称> [--scope 'glob'] [--network] [--base 引用]` | 创建 worktree、分支、任务状态和任务说明。默认**不开网络**。 |
| `dispatch.sh <名称> [--detach]` | 检查任务说明、Agent 可用性、并发上限、文件重叠，然后开始/继续运行。 |
| `drive.sh <名称>` | 调度循环本身（dispatch 会调用）。 |
| `feedback.sh <名称> "文字"` | 给任务追加反馈；只有在一轮成功后才确认送达，失败会重发。 |
| `verify.sh <名称>` | 调度器自己在任务 worktree 里运行 `AGENT_VERIFY_CMD`，结果绑定当前 commit。 |
| `review.sh <名称> approve\|changes "说明"` | 记录审查结论（绑定 SHA）；`changes` 会转成反馈。 |
| `integrate.sh <名称>` | 门禁检查后在集成 worktree 合并，再验证，失败回滚；冲突时停下并说明。 |
| `ship.sh` | 只构建/安装已验证的集成 SHA（运行 `AGENT_SHIP_CMD`）。 |
| `status.sh [--json\|--markdown\|--sync TASKS.md]` | 所有任务的状态、轮数、token、验证、审查、待送达反馈；能识别进程已死的「stalled」任务。 |
| `report.sh <名称>` | 单个任务的 Markdown 报告（改动文件、Agent 报告、验证日志）。 |
| `conflicts.sh [名称]` | 检测任务之间的文件重叠，并用 `git merge-tree` 预测与集成分支的冲突。 |
| `stop.sh <名称>` | 停止任务（整个进程树），保留已改内容和未送达的反馈。 |
| `alert.sh "消息"` | 重复提示音直到你点停止（macOS 需在沙箱外运行；Linux 用 notify-send）。 |

## 安装

需要：[Claude Code](https://claude.com/claude-code)、[Codex CLI](https://github.com/openai/codex)（或 Codex 桌面端自带的 CLI）、git ≥ 2.31、bash、python3（或 jq）。可选：`gh`（GitHub 维护）、git ≥ 2.38（冲突预测）。

作为插件安装（技能 + 子 Agent）：

```
/plugin marketplace add mu-zi-lee/hitl-dev-loop
/plugin install hitl-dev-loop@hitl-dev-loop
```

或者只复制技能：

```bash
git clone https://github.com/mu-zi-lee/hitl-dev-loop
cp -r hitl-dev-loop/skills/hitl-dev-loop ~/.claude/skills/
cp hitl-dev-loop/PROTOCOL.md ~/.claude/skills/hitl-dev-loop/   # 复制安装时 PROTOCOL.md 放在技能旁边
cp hitl-dev-loop/agents/repo-maintainer.md ~/.claude/agents/   # 可选
```

## 使用

在你的项目里启动 Claude Code，直接说：

> 用 hitl-dev-loop 的方式开发这个项目。先检查项目状态，告诉我需要做哪些最小改动。

Claude 会先汇报情况，等你同意后再建立 `AGENTS.md`、`CLAUDE.md`、任务队列和决策记录，运行 `init.sh`，并在 `.agent-loop/config.sh` 里配置验证命令。之后你只要描述问题（「这个页面太窄了」「打开是白屏」+ 截图），Claude 会写任务说明、派发、审查、集成，做完叫你来试。

也可以手动使用：

```bash
S=~/.claude/skills/hitl-dev-loop/scripts
$S/init.sh
echo "AGENT_VERIFY_CMD='make test'" >> .agent-loop/config.sh
$S/new-task.sh reader-fonts --scope 'src/reader/*'
$EDITOR .agent-loop/briefs/reader-fonts.md
$S/dispatch.sh reader-fonts --detach
$S/feedback.sh reader-fonts "正文在 1280px 宽度下溢出"
$S/status.sh
$S/report.sh reader-fonts
$S/review.sh reader-fonts approve
$S/integrate.sh reader-fonts
$S/ship.sh && $S/alert.sh "可以验收了"
```

### 配置（`.agent-loop/config.sh`，自动加入 git 忽略）

| 变量 | 默认 | 作用 |
|---|---|---|
| `AGENT_VERIFY_CMD` | 空 | 调度器独立运行的完整验证。不设置时任务停在 `needs-review`。 |
| `AGENT_SHIP_CMD` | 空 | 构建并安装产品以便你验收（在集成 worktree 中运行，可用 `$SHIP_SHA`）。 |
| `AGENT_COMMITS` | `scheduler` | 由调度器提交（Agent 无法写 git 元数据）；设为 `agent` 则由 Agent 自己提交。 |
| `DEFAULT_NETWORK` | `0` | 新任务的网络权限；单个任务用 `--network` 开启。 |
| `MAX_PARALLEL` / `MAX_ROUNDS` | 3 / 15 | 并行任务数 / 每次运行的最大轮数。 |
| `MAX_FAILS` / `MAX_VERIFY_FAILS` | 3 / 3 | 连续 Agent 失败 / 验证失败的熔断阈值。 |
| `ROUND_TIMEOUT` / `VERIFY_TIMEOUT` | 3600 | 单轮 / 单次验证的超时（秒）。 |
| `TASK_TIME_BUDGET` / `TOKEN_BUDGET` | 0 | 每个任务的总时长 / token 预算，0 为不限。 |
| `CODEX_BIN`、`CODEX_WRITABLE_DIRS`、`CODEX_EXTRA_ARGS` | 自动 | Codex 路径、额外可写目录（构建缓存）、额外参数。 |
| `INTEGRATION_BRANCH` | `codex/integration` | 集成分支。 |

## 内置的经验

都是在真实项目里踩坑后总结的，部分与 Codex CLI 版本有关（在 codex-cli 0.162 实测），升级后值得重新验证：

- `codex exec` 经常只汇报一句进度就结束 → 调度循环自动续跑，完成由调度器判定。
- 只要 stdin 没关，`codex exec` 就会一直等输入；非交互 bash 里后台任务的 stdin 会被换成 `/dev/null` → 脚本显式处理两种情况。
- 失败的启动也会先发出 `thread.started` → 必须同时看退出码和 `turn.failed`，只保存成功启动的会话。
- 当时版本的 Codex goal 功能会因模型给自己设极小的 token 预算而卡住，`exec fork` 还会继承 → 不依赖它。
- Codex 沙箱常常写不了 worktree 的 git 索引 → 默认改为调度器提交。
- Agent 曾在主仓库的 `.git/config` 里写入 `core.worktree`，导致主目录里所有 git 命令都作用到另一个目录 → 调度器每轮之后检查并复原共享配置、提醒 Agent，`dispatch.sh` 遇到已被改坏的配置会拒绝启动；仓库根目录改由 `--git-common-dir` 推算，不受它影响。
- 每改一点就跑全量测试会让任务跑一两个小时 → Agent 只跑相关测试，全量验证由调度器在提交后跑一次。
- 同时跑太多 Agent 会让每个都变慢 → 并发上限 + 文件重叠检测。
- 笼统的「暂时不可用」浪费轮次 → 让代码把状态码、内容类型、最终网址、脱敏片段显示出来。
- macOS 沙箱里 `afplay` 执行成功但没有声音 → `alert.sh` 要在沙箱外运行。

## 开发与测试

```bash
tests/run.sh            # 全部 21 个场景（模拟 Codex，不需要网络和 API）
tests/run.sh timeout    # 按名称过滤
shellcheck -S warning skills/hitl-dev-loop/scripts/*.sh skills/hitl-dev-loop/scripts/adapters/*.sh
```

## 许可证

MIT
