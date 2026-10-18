# hitl-dev-loop

**面向 Claude Code + Codex CLI 的人机协作（Human-in-the-Loop）开发循环。**

Claude 担任主 Agent：理解你的需求、调研、拆解任务，把编码工作派给在独立 git worktree 中运行的 Codex CLI，推动它做完，审查改动，集成、构建，然后提醒你来验收。你只需要体验真实的软件，用大白话或截图反馈，并决定产品方向和发布。

这不是无人监督的自动编程，而是一个把你的反馈不断变成「已验证的改动」、同时由你掌握方向的开发循环。

## 包含什么

| 路径 | 说明 |
|---|---|
| `skills/hitl-dev-loop/SKILL.md` | Claude 遵循的完整流程：首次接入、需求分析、任务说明、调度 Codex、审查、集成、授权边界、任务队列、Token 管理。 |
| `skills/hitl-dev-loop/scripts/` | Bash 辅助脚本：`init.sh`、`new-task.sh`、`dispatch.sh`、`drive.sh`、`resume.sh`（含反馈收件箱）、`status.sh`、`ship.sh`、`alert.sh`。 |
| `skills/hitl-dev-loop/templates/` | `AGENTS.md`、`CLAUDE.md`、`TASKS.md`、`DECISIONS.md` 模板，所有 Codex 任务共用的规则，以及任务说明模板。 |
| `agents/repo-maintainer.md` | 低成本、只读的子 Agent：整理 GitHub Issue / PR，把需要决策的事项汇报给主 Agent。 |

## 安装

需要：[Claude Code](https://claude.com/claude-code)、[Codex CLI](https://github.com/openai/codex)（或 Codex 桌面端自带的 CLI）、git、bash。可选：用于 GitHub 维护的 `gh`。

作为插件安装（技能 + 子 Agent）：

```
/plugin marketplace add mu-zi-lee/hitl-dev-loop
/plugin install hitl-dev-loop@hitl-dev-loop
```

或者只复制技能：

```bash
git clone https://github.com/mu-zi-lee/hitl-dev-loop
cp -r hitl-dev-loop/skills/hitl-dev-loop ~/.claude/skills/
cp hitl-dev-loop/agents/repo-maintainer.md ~/.claude/agents/   # 可选
```

## 使用

在你的项目里启动 Claude Code，直接说：

> 用 hitl-dev-loop 的方式开发这个项目。先检查项目状态，告诉我需要做哪些最小改动。

Claude 会先汇报它看到的情况（架构、已有文档、测试能力、哪些工具可用），等你同意后再创建 `AGENTS.md`、`CLAUDE.md`、任务队列和决策记录，并运行 `init.sh`。之后你只要描述问题就行，比如「这个页面太窄了」「Linux.do 话题打开是白屏」再附一张截图。Claude 会写好任务说明、派给 Codex，做完后叫你来试。

这些脚本也可以手动使用：

```bash
S=~/.claude/skills/hitl-dev-loop/scripts   # 或插件安装后的路径
$S/init.sh                     # 每个仓库运行一次：创建 .agent-loop/ 和集成分支
$S/new-task.sh reader-fonts    # 在 ../<仓库名>-wt/reader-fonts 建 worktree，分支 codex/reader-fonts
$EDITOR .agent-loop/briefs/reader-fonts.md   # 填写任务说明
$S/dispatch.sh reader-fonts &  # 启动 Codex；续跑循环会推着它直到「已完成」并提交
echo "正文在 1280px 宽度下溢出" > .agent-loop/feedback/reader-fonts.md   # 给运行中的任务追加反馈
$S/status.sh                   # 查看各任务：提交数 / 未提交改动 / 是否完成 / 待送达反馈 / 是否运行中
$S/alert.sh "可以验收了"        # 重复提示音直到你点停止（macOS，需在沙箱外运行）
```

每个仓库的配置写在 `.agent-loop/config.sh`（已自动加入 git 忽略）：

| 变量 | 作用 |
|---|---|
| `CODEX_BIN` | Codex CLI 路径（默认找 PATH，再找 Codex 桌面端自带的） |
| `CODEX_WRITABLE_DIRS` | 允许 Codex 写入的额外目录，如构建缓存 `~/Library/Caches/go-build:~/go:~/.npm` |
| `INTEGRATION_BRANCH` | 集成分支，默认 `codex/integration` |
| `AGENT_SHIP_CMD` | 构建并安装应用以便你手动验收的命令 |
| `DONE_MARKER` | 判定任务完成的回复开头，默认 `【已完成】` 或 `[DONE]` |
| `MAX_ROUNDS` | 续跑循环的最大轮数，默认 15 |

## 内置的经验

这些规则都是在真实项目里踩坑后总结出来的：

- `codex exec` 经常只汇报一句进度就结束 → 用不依赖 goal 的续跑循环（`drive.sh`），只有回复「已完成」**并且**分支有新提交才停。
- Codex 的 goal 功能会因为模型给自己设了极小的 token 预算而卡住，`exec fork` 还会继承这个限制 → 不使用。
- Codex 沙箱经常写不了 worktree 的 git 索引 → 读取状态前先 `git reset -q` 同步；合并前核对提交的祖先关系和内容。
- 每改一点就跑全量测试，会让一个任务跑一两个小时 → 改代码时只跑相关测试，提交前跑一次全量。
- 同时跑太多 Codex 会让每个都变慢 → 同时最多 2～3 个，任务之间要有明确的文件边界；新的反馈交给已经在改这些文件的任务，而不是新开一个。
- 笼统的「暂时不可用」会白白浪费好几轮 → 先让代码把状态码、内容类型、最终网址、脱敏后的响应片段显示出来，再根据用户真实环境里的诊断去修。
- macOS 沙箱里 `afplay` 执行成功但没有声音 → `alert.sh` 要在沙箱外运行。
- 推送、打 tag、发布、关闭 Issue、合并 PR，永远要先得到你的明确同意。

## 许可证

MIT
