#!/usr/bin/env bash
#
# experience-report-repro —— 一键安装 opencode Skill
#
# 把仓库内的 SKILL.md 安装为 opencode Skill(也兼容 Claude Code)。
#
# opencode skill 目录约定:
#   全局: ~/.config/opencode/skills/<name>/SKILL.md
#   项目: <dir>/.opencode/skills/<name>/SKILL.md
# Claude Code skill 目录约定:
#   用户级: ~/.claude/skills/<name>/SKILL.md
#   项目级: <dir>/.claude/skills/<name>/SKILL.md
#
# 用法:
#   ./install.sh                     安装为用户级 opencode skill (~/.config/opencode/skills/experience-report-repro/)
#   ./install.sh --link              用软链安装, git pull 后自动生效
#   ./install.sh --project <dir>     安装为项目级 opencode skill (<dir>/.opencode/skills/experience-report-repro/)
#   ./install.sh --claude            改装到 Claude Code (~/.claude/skills/experience-report-repro/)
#   ./install.sh --claude --project <dir>  装为 Claude Code 项目级 skill (<dir>/.claude/skills/experience-report-repro/)
#   ./install.sh --help              查看帮助
#
set -euo pipefail

SKILL_NAME="experience-report-repro"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SKILL="$SCRIPT_DIR/SKILL.md"

usage() {
  cat <<EOF
experience-report-repro 安装脚本

把仓库内的 SKILL.md 安装为 opencode Skill(默认),也支持 Claude Code。

用法:
  ./install.sh                   安装为用户级 opencode skill
                                 (默认目标: ~/.config/opencode/skills/$SKILL_NAME/)
  ./install.sh --link            用软链安装 (git pull 后自动更新, 无需重装)
  ./install.sh --project <dir>   安装为项目级 opencode skill (<dir>/.opencode/skills/$SKILL_NAME/)
  ./install.sh --claude          改装到 Claude Code (~/.claude/skills/$SKILL_NAME/)
  ./install.sh --claude --project <dir>  装为 Claude Code 项目级 skill (<dir>/.claude/skills/$SKILL_NAME/)
  ./install.sh --help            显示本帮助

说明:
  - 默认目标为 opencode (全局 ~/.config/opencode/skills/);加 --claude 改装到 Claude Code。
  - 默认使用复制安装。--link 改用软链, 适合开发 / 频繁更新场景。
  - 若目标已存在同名 SKILL.md (非软链), 会先备份为 SKILL.md.bak 再覆盖。
  - 仓库内已自带 .opencode/skills/$SKILL_NAME/ 软链, 在本仓库里直接用 opencode 即可自动加载, 无需安装。
EOF
}

if [[ ! -f "$SRC_SKILL" ]]; then
  echo "错误: 未找到仓库内的 SKILL.md ($SRC_SKILL)" >&2
  exit 1
fi

TARGET="opencode"    # opencode | claude
MODE="user"          # user | project
USE_LINK="false"
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --link)    USE_LINK="true"; shift ;;
    --claude)  TARGET="claude"; shift ;;
    --project)
      MODE="project"
      shift
      if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
        PROJECT_DIR="$1"; shift
      fi
      ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$MODE" == "project" ]]; then
  if [[ -z "$PROJECT_DIR" ]]; then
    echo "错误: --project 需要指定一个项目目录" >&2
    exit 1
  fi
  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "错误: 项目目录不存在: $PROJECT_DIR" >&2
    exit 1
  fi
  if [[ "$TARGET" == "claude" ]]; then
    DEST_DIR="$(cd "$PROJECT_DIR" && pwd)/.claude/skills/$SKILL_NAME"
  else
    DEST_DIR="$(cd "$PROJECT_DIR" && pwd)/.opencode/skills/$SKILL_NAME"
  fi
else
  if [[ "$TARGET" == "claude" ]]; then
    DEST_DIR="${HOME}/.claude/skills/$SKILL_NAME"
  else
    DEST_DIR="${HOME}/.config/opencode/skills/$SKILL_NAME"
  fi
fi

DEST_SKILL="$DEST_DIR/SKILL.md"
mkdir -p "$DEST_DIR"

# 备份已存在的普通文件 (非软链)
if [[ -e "$DEST_SKILL" && ! -L "$DEST_SKILL" ]]; then
  cp "$DEST_SKILL" "$DEST_SKILL.bak"
  echo "已备份旧文件 -> $DEST_SKILL.bak"
fi

# 若已存在软链 / 文件, 先移除
rm -f "$DEST_SKILL"

if [[ "$USE_LINK" == "true" ]]; then
  ln -s "$SRC_SKILL" "$DEST_SKILL"
  echo "✓ 已软链安装 (link) [$TARGET]:"
  echo "  $DEST_SKILL -> $SRC_SKILL"
else
  cp "$SRC_SKILL" "$DEST_SKILL"
  echo "✓ 已复制安装 (copy) [$TARGET]:"
  echo "  $DEST_SKILL"
fi

cat <<EOF

安装完成。

下一步:
  1. 打开 opencode (CLI / IDE 插件);
  2. 给出一份体验评估 JSON 报告, 并指定要复现的阶段, 例如:
     "这是 experience_report.json, 请复现并核实 S3 编译阶段的失败结论。"

提示:
  - 本仓库已自带 .opencode/skills/$SKILL_NAME/ 软链, 在仓库内直接用 opencode 即可自动加载, 无需运行本脚本。
  - 配置变更后需退出并重启 opencode 才能生效。

升级:
  - copy 模式: 重新执行 ./install.sh 即可;
  - link  模式: git pull 后自动生效, 无需重装。

卸载:
  rm -rf "$DEST_DIR"
EOF
