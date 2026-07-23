# Multi-Agent Coding Workflow

这是一个可持续迭代的多 Agent 编码工作流：GLM-5.2 负责需求分析、规划与测试编写，Kimi K3 专注代码实现，MiMo 2.5 Pro 负责执行测试并返回错误回执，Basic Memory 提供完全本地的跨项目记忆。

工作项目只看到统一的本地目录 `.workflow/`。不会向业务仓库根目录写入配置 JSON、Agent 目录或脚本；唯一的仓库级改动是在 `.gitignore` 中声明 `.workflow/`。用户只使用 `workflow` 命令，不需要感知底层 Agent harness。

## 工作流

```text
用户需求
  -> planner (GLM-5.2): 召回线索、分析需求、定义验收标准
  -> test-writer (GLM-5.2): 先写测试并给出精确执行命令
  -> test-runner (MiMo 2.5 Pro): 执行测试并返回结构化失败回执
  -> coder (Kimi K3): 完成最小实现并让测试通过
  -> test-runner (MiMo 2.5 Pro): 执行回归并返回 PASS/FAIL/BLOCKED 回执
  -> test-writer (GLM-5.2): 检查断言与最终 diff
  -> planner (GLM-5.2): 仅在 PASS 后写入已验证记忆并汇总
```

`planner` 是默认主 Agent，`coder`、`test-writer` 和 `test-runner` 是受限子 Agent。当前在同一工作区中顺序执行，不自动创建 worktree，不自动提交或推送。

## 安装

要求：macOS 或 Linux、Git、curl、Node.js 20+、Kimi K3 API Key、MiMo API Key、DeepSeek API Key、智谱 GLM Coding Plan API Key。

```bash
git clone git@github.com:wenshiqi0/teamflow.git
cd teamflow
./scripts/bootstrap.sh
```

`bootstrap.sh` 会安装或升级底层运行时、uv、Basic Memory，并把统一入口安装到 `~/.local/bin/workflow`。如该目录不在 `PATH`，将它加入 shell 配置：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

在全局的 `~/.workflow/.env` 中配置模型密钥，或直接使用 shell 环境变量：

```dotenv
KIMI_API_KEY=your-kimi-api-key
ZHIPU_API_KEY=your-zhipu-coding-plan-api-key
MIMO_API_KEY=your-mimo-api-key
DEEPSEEK_API_KEY=your-deepseek-api-key
```

shell 环境变量优先级最高；业务项目的 `.workflow/.env` 可作为少数项目的本地覆盖，但默认不需要创建。

初始化本地跨项目记忆并检查模板：

```bash
./scripts/setup-memory.sh
./scripts/doctor.sh
```

## 初始化工作项目

先预览：

```bash
./scripts/init-project.sh --dry-run /path/to/project
```

再安装：

```bash
./scripts/init-project.sh /path/to/project
cd /path/to/project
workflow
```

无头运行：

```bash
workflow run --agent planner "为当前项目增加一个健康检查接口"
```

安装器遵循最小 Git 侵入原则：

- 所有运行文件只写入项目的 `.workflow/`。
- `.gitignore` 只增加 `.workflow/` 及一行中性说明，便于团队共享这一目录约定。
- 业务项目已有的 `AGENTS.md`、配置、脚本和源码完全保留。
- manifest 位于 `.workflow/manifest.json`，用于幂等更新和冲突检测。
- 用户修改过的受管文件不会被静默覆盖；`--force` 会先备份到 `~/.workflow/backups/`。

除 `.gitignore` 的标准目录规则外，安装前后业务仓库的 `git status --short` 应保持不变。

## 目标项目布局

```text
.workflow/                    # 整个目录仅本地存在
├── config.json               # 工作流运行配置
├── manifest.json             # 安装器校验信息
├── instructions/
│   └── AGENTS.md             # 工作流共享约束
├── agents/
│   ├── planner.md
│   ├── test-writer.md
│   ├── test-runner.md
│   └── coder.md
├── skills/
├── bin/                      # 仅正式流程入口
│   ├── workflow              # 项目内入口
│   ├── memory                # 本地记忆适配器
│   ├── memory-capture        # 已验证任务的正式记忆链路
│   └── test-patch            # 测试补丁门禁
├── experiments/bin/          # 显式调用的临时实验，不由 workflow 命令暴露
└── runs/                     # 临时运行产物
```

全局 `workflow` 命令只负责定位当前 Git 项目，再调用 `.workflow/bin/workflow`。包装器通过显式配置路径加载 Agents 和 Skills，因此业务根目录不需要任何 harness 配置或目录。

## 旧安装迁移

重新执行初始化器会迁移旧布局：

- 删除由旧安装器管理且未被用户修改的根级 `opencode.json`。
- 删除旧 `.opencode/` 运行目录。
- 删除旧 `scripts/opencode.sh` 和 `scripts/memory.sh`。
- 移除旧安装器写入 `.gitignore` 的精确规则块。
- 将新布局安装到 `.workflow/`，并统一由 `.gitignore` 忽略。

检测到用户修改或无法识别的旧文件时会停止。只有显式使用 `--force` 才会备份后迁移。

## 模型配置

| Agent | Model | 权限 |
| --- | --- | --- |
| `planner` | GLM-5.2 | 需求分析、规划和调用指定子 Agent；不修改业务代码 |
| `test-writer` | GLM-5.2 | 只负责测试设计、测试文件和最终断言审查 |
| `test-runner` | MiMo 2.5 Pro | 只执行测试并返回结构化错误回执；禁止修改文件 |
| `coder` | Kimi K3 | 专注修改代码、构建和测试；禁止危险 Git 操作 |
| `command` | MiMo 2.5 Pro | 快速执行明确的 Shell、Git、GitHub 操作；禁止修改代码和启动子 Agent |

记忆候选生成使用四个隔离阶段：`emotional-salience-sensor`（MiMo 2.5 Pro）探测可观察信号与记忆显著性，`memory-compressor`（DeepSeek V4 Pro）压缩原始长记忆，`memory-extractor`（GLM-5.2）发现概念与经验，`memory-formatter`（GLM-5.2）生成原子化候选。正式 formatter 固定使用 GLM-5.2，作为稳定输出骨架；其他模型只通过实验目录临时对比。Emotion 只提供注意力元数据，不进行心理诊断、不主动追问，也不能作为事实证据或直接写入记忆。

当前模型端点：

- Kimi Code：`https://api.kimi.com/coding/v1`
- MiMo OpenAI-compatible：`https://token-plan-cn.xiaomimimo.com/v1`
- DeepSeek：`https://api.deepseek.com`（`deepseek/deepseek-v4-pro`）
- 智谱 GLM Coding Plan：`https://open.bigmodel.cn/api/coding/paas/v4`

底层配置使用当前稳定版 OpenCode schema；这一实现细节封装在 `.workflow/bin/workflow` 内，日常使用不直接调用 OpenCode 命令。

明确的命令式任务不启动 GLM planner 与 K3 coder，直接使用快速命令模式：

```bash
workflow command "检查当前 diff，提交到 feat/example 并创建 PR"
```

该模式由 MiMo 2.5 Pro 执行，仅适用于无需修改业务内容的状态检查、测试执行、分支、提交、push 和 PR 操作；危险清理、强制推送、代码编辑和子 Agent 委派均被禁止。

OpenCode 以流式方式消费模型响应。所有 provider 都显式设置 `timeout: false` 与 `headerTimeout: false`，且不配置 `chunkTimeout`，因此本地不会因为等待响应头、provider 排队或流式 chunk 暂停而主动结束请求。明确的 provider timeout、认证失败、额度不足、overload、传输失败、用户取消或进程退出仍必须结束当前阶段并返回真实的 `BLOCKED`；不能把错误折叠为空结果或静默重试整轮。`workflow phase status --run-id <id>` 查看当前阶段，增加 `--phase <name>` 可读历史阶段回执；其中 stale 只表示观察时间较长，不会终止模型。K3 每批编辑后必须运行 `workflow source-check`，它会拒绝 NUL、ESC、DEL 等误入源码的非打印控制字节。

记忆 Agent 默认同样无限等待 provider。只有显式设置正整数 `WORKFLOW_MODEL_STAGE_TIMEOUT_SECONDS` 才启用本地 wall-time；零、负数和非整数会被拒绝。若显式 timeout 或 provider 错误发生在 extraction 之后，使用 `workflow memory-capture --receipt <file> --resume-formatting <run-id>`，不重跑已完成阶段；启用 timeout 时仍会终止整个子进程组，避免后台孤儿继续执行 apply。

workflow 仓库自身的外层协调器使用 `skills/outer-loop-monitor/` 监听内层 OpenCode loop。脚本依据 root/child session、message finish、part/tool 状态、phase receipt、预期产物和分类后的 provider 错误输出元数据快照或 NDJSON heartbeat，不读取或输出 prompt、reasoning、response、原始错误与凭证。`WAITING_PROVIDER` 和 `DELEGATED_WAITING_PROVIDER` 表示继续等待，不是断联。该 Skill 不在 `.workflow/` 下，也不会由 `scripts/init-project.sh` 安装到目标项目。

单次任务默认最多自动创建 8 条新记忆；超出时 deterministic validation/apply 会在任何写入前整体拒绝。可通过 `WORKFLOW_MEMORY_MAX_CREATES_PER_RUN` 显式调整，但不建议常态放宽。

## 本地跨项目记忆

默认目录：

```text
~/.workflow/memory/
├── knowledge/    # Markdown source of truth
└── state/        # Basic Memory 配置、SQLite、日志和缓存
```

默认 Basic Memory project 为 `workflow`。全部操作强制使用本地模式，不需要账号、邮箱、云 API 或 MCP。

```bash
workflow memory status
workflow memory recall "Agent 权限配置"
workflow memory list
workflow memory read "memory://<note-permalink>"
workflow memory context "memory://<topic>/*"
workflow memory remember "已验证的项目事实；证据：相关测试 PASS。"
workflow memory remember-global "已在多个项目验证的通用实践。"
```

`remember`/`remember-global` 仅保留给显式手工写入；编码任务收尾禁止直接调用，必须生成 verified-task receipt 后运行 `workflow memory-capture`。

实验性运行完整记忆候选流程（只生成候选，不写 Basic Memory）：

```bash
.workflow/experiments/bin/memory-experiment \
  --source memory://workflow/projects/example/finding-a \
  --source memory://workflow/projects/example/finding-b
```

每次运行产物位于 `.workflow/runs/memory/<run-id>/`：证据胶囊、Emotion 输入与信号、DeepSeek 压缩结果、GLM 抽取与格式化结果、阶段日志与确定性校验报告均独立保存。四个阶段固定串行运行，以避免本地状态锁。Emotion 的高强度或高显著性只要求压缩阶段保留目标或说明排除理由，不会自动升级为知识。若下游阶段的可解析 JSON 违反结构或谱系约束，runner 最多把精确错误回执交给同一阶段修复一次；第二次仍失败则整轮停止。

任务通过测试与最终审查后，Planner 写入 `.workflow/runs/task-receipts/<run-id>/receipt.json` 并运行：

```bash
workflow memory-capture --receipt .workflow/runs/task-receipts/<run-id>/receipt.json
```

安全 apply 只自动写入新的原子候选；`update`、`supersede` 和冲突保留在 `50-apply.json`，不会覆盖旧记忆或打断用户询问。

需要比较某个阶段的模型效果时使用临时模型覆盖，不新增固定 Agent，也不执行 apply：

```bash
.workflow/experiments/bin/memory-compare \
  --run-id <existing-run-id> \
  --stage formatting \
  --model zhipuai-coding-plan/glm-5.2 \
  --label glm52
```

比较产物与基线并存，报告候选数量、动作分布、类型、谱系校验和 atomic source retain 情况。`compression`、`extraction`、`formatting` 均可按需比较。

测试由 GLM 生成统一补丁到 `.workflow/runs/test-patches/`。`workflow test-patch check` 确认改动仅位于普通测试文件或 Rust `#[cfg(test)] mod ...` 后，K3 才可用 `workflow test-patch apply` 机械应用。

可配置项：

- `WORKFLOW_HOME`：默认 `$HOME/.workflow`
- `WORKFLOW_MEMORY_HOME`：默认 `$WORKFLOW_HOME/memory`
- `WORKFLOW_MEMORY_PROJECT`：默认 `workflow`

首次运行 `setup-memory.sh` 时，如果发现旧的 `~/.opencode-workflow/memory` 且新目录不存在，会迁移到 `~/.workflow/memory`。旧环境变量仍作为兼容回退，但新文档和命令不再暴露底层 harness 名称。

记忆策略：先搜索、后验证，只在全部质量门 PASS 后写入；禁止保存密钥、隐私数据、原始对话、完整日志或未验证猜测。

## 维护与诊断

查看工作流实际发现的 Agent 和 Skill：

```bash
workflow debug agent planner
workflow debug agent coder
workflow debug agent test-writer
workflow debug agent test-runner
workflow debug skill
```

更新 Basic Memory 官方 Skills 的 CLI-only 适配：

```bash
./scripts/update-basic-memory-skills.sh \
  --ref main \
  --instruction "保留新增的本地知识图谱能力，继续禁止云端与 MCP"
```

模板仓库结构：

```text
.
├── AGENTS.md
├── README.md
├── .env.example
├── .workflow/             # 可安装运行模板
│   ├── config.json
│   ├── instructions/
│   ├── agents/
│   ├── skills/
│   └── bin/
└── scripts/
    ├── bootstrap.sh
    ├── doctor.sh
    ├── init-project.sh
    ├── setup-memory.sh
    ├── update-basic-memory-skills.sh
    └── workflow           # 全局入口模板
```

## 迭代原则

1. 对业务仓库保持最小 Git 侵入：只声明 `.workflow/` 忽略规则，所有实现集中在该目录。
2. 先修改工作流规则、Agent 或 Skill，再用真实任务验证。
3. 测试必须在实现前证明缺失行为，最终必须重新运行。
4. Agent 不得自行推送、强制重置或清理用户工作区。
5. 调整模型、权限、交接协议或安装链路时，同步 README 和 `AGENTS.md`。
6. 跨项目记忆保留来源且使用前重新验证，不能替代当前仓库事实。
