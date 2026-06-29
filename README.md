# experience-report-repro

> 在固定的昇腾 NPU Docker 容器里，复现体验评估 JSON 报告中某个阶段的命令轨迹，核实报告里的痛点 / 失败结论是否真的成立。

这是一个 [opencode](https://opencode.ai) Skill（同时兼容 Claude Code）。

## 它做什么

把"体验评估 Agent"生成的 JSON 报告交给 opencode，并指定要复现的阶段（如"复现 S3 编译阶段"），它会：

1. 严格按报告 `S1_SETUP` 把容器环境配成与报告一致（环境基线）；
2. 逐条复现指定阶段的命令轨迹，捕获真实退出码与业务输出；
3. 逐条核实该阶段的痛点 / 失败结论是否成立，输出一份 `repro_report.md`。

核心理念：**S1 是环境基线**，判定成败看**真实结果**（不被 `| tail` 等管道骗到）——很多"痛点 / 失败"其实是评估那次的特定环境或用法问题，而非项目缺陷。

## 前置要求

- 宿主机有 Ascend NPU 驱动 / firmware / `npu-smi`；
- 可运行 Docker（需挂载 `/dev/davinci*`）；
- 已安装 opencode（或 Claude Code，skill frontmatter 两者兼容）；
- 一份体验评估 Agent 生成的 JSON 报告（结构见 [SKILL.md](SKILL.md)「JSON 报告结构速查」）。

## 安装

仓库内已自带 `.opencode/skills/experience-report-repro/` 软链指向根 `SKILL.md`——**在本仓库里直接用 opencode 即可自动加载，无需运行安装脚本**。要在别的项目 / 全局使用，再运行：

```bash
git clone <repo-url> experience-report-repro
cd experience-report-repro
./install.sh            # 安装为用户级 opencode skill（~/.config/opencode/skills/experience-report-repro/）
```

`install.sh` 选项：

| 选项 | 说明 |
|---|---|
| （无）| 复制到用户级 `~/.config/opencode/skills/experience-report-repro/`（opencode 全局） |
| `--link` | 软链安装，`git pull` 后自动更新 |
| `--project <dir>` | 装为项目级 opencode skill `<dir>/.opencode/skills/experience-report-repro/` |
| `--claude` | 改装到 Claude Code（`~/.claude/skills/experience-report-repro/`），可与 `--project` 叠加 |

也可手动：`cp SKILL.md ~/.config/opencode/skills/experience-report-repro/SKILL.md`。

> opencode 还会自动扫描 `~/.claude/skills/` 与 `~/.agents/skills/` 下的 `SKILL.md` 作为外部 skill，因此旧的 Claude Code 安装在 opencode 里也能直接生效。

## 使用

在 opencode 里给出报告并指定阶段：

```
这是 experience_report.json，请复现并核实 S3 编译阶段的失败结论。
```

- **输入**：JSON 体验报告 + 指定阶段（S2 / S3 / S4 等，须 `not_evaluated=False` 且有 actions）。
- **输出**：归档到 `test_<项目名>/`，结论报告固定写入 `test_<项目名>/log/repro_report.md`。
- **流程**：执行阶段（起容器 → 按 S1 配环境 → 逐条复现，严格忠于报告、不翻文档）→ 分析阶段（引入文档逐条核实痛点、三分类归因、写结论）。

完整规则、JSON 取数路径、报告模板见 [SKILL.md](SKILL.md)。

## 配置

SKILL.md 里以下值为默认基线，可按需替换：镜像 `guoqiangqi/cogito:202606150944`、容器名 `cann_test_{使用者}_{项目名}`（`{使用者}` 为使用者自己的标识，如姓名缩写）、工作目录 `test_<项目名>/`。

## 许可证

[MIT](LICENSE)
