#!/usr/bin/env bash
# 构建期给 webui 打 virtual [project] 表（上游无 [project]，从不 pip install 自身）。
# 使其成为 uv workspace member：dependencies 自动解析自上游 requirements.txt
# （可选依赖均为注释，与官方镜像一致）；package=false 不安装自身。
# 用法: patch-webui-pyproject.sh <webui_dir> [version]
set -euo pipefail

dir="${1:?usage: patch-webui-pyproject.sh <webui_dir> [version]}"
version="${2:-0.0.0}"
version="${version#v}"   # PEP 440 去 v 前缀
file="$dir/pyproject.toml"
req="$dir/requirements.txt"

[ -f "$file" ] || { echo "[patch] ERROR: $file not found" >&2; exit 1; }
[ -f "$req" ] || { echo "[patch] ERROR: $req not found" >&2; exit 1; }

# 上游已有 [project] 表（如 master 分支：完整打包配置）→ 无需 patch
if grep -q '^\[project\]' "$file"; then
    echo "[patch] upstream already has [project] table, skipping"
    exit 0
fi

# 幂等：已打补丁则跳过
if grep -q 'Private :: Do Not Upload' "$file"; then
    echo "[patch] already applied, skipping"
    exit 0
fi

# 解析 requirements.txt 硬依赖（去注释/空行）
deps=""
while IFS= read -r line; do
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    deps="${deps}    \"${line}\",
"
done < "$req"

cat >> "$file" <<EOF

[project]
name = "hermes-webui"
version = "${version}"
classifiers = ["Private :: Do Not Upload"]
dependencies = [
${deps}]

[tool.uv]
package = false
EOF

echo "[patch] applied virtual [project] table to $file"
