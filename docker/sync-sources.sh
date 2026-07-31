#!/usr/bin/env bash
# 生成 temp/ 构建素材（本地 / CI / 宿主机复用；temp/ 不入 git）：
# 上游源码 checkout + webui patch + workspace 根 + uv.lock
# 用法: bash docker/sync-sources.sh [AGENT_REF] [WEBUI_REF]
#   REF 取值：留空/auto = 最新 release tag；main = main 分支最新 commit；
#            其他 = 显式 tag / 分支 / commit sha
# 解析结果写入 temp/versions.env（供 build.sh / CI build-args / 镜像标签）
set -euo pipefail
cd "$(dirname "$0")/.."

# 探测上游最新 release tag：优先 gh api（认证、限流宽松），fallback git ls-remote
detect_latest_tag() {
    local repo="$1" pattern="$2" tag="" gh_repo err_file
    err_file="$(mktemp)"
    gh_repo="$(printf '%s' "$repo" | sed -E 's|https://github.com/([^/]+)/([^/]+?)(\.git)?$|\1/\2|')"
    if command -v gh >/dev/null 2>&1 && [ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]; then
        tag="$(gh api "repos/${gh_repo}/releases/latest" --jq '.tag_name' 2>"$err_file" || true)"
        printf '%s' "$tag" | grep -qE "$pattern" || tag=""   # 校验 release tag 形态
    fi
    if [ -z "$tag" ]; then
        tag="$(git ls-remote --tags --refs "$repo" 2>>"$err_file" \
            | awk -F/ '{print $NF}' | grep -E "$pattern" | sort -V | tail -1 || true)"
    fi
    if [ -z "$tag" ]; then
        echo "[detect] 解析失败：$repo" >&2
        sed 's/^/    /' "$err_file" >&2 || true
    fi
    rm -f "$err_file"
    echo "$tag"
}

# 解析 REF：auto → 最新 release tag；main/latest → 默认分支最新 commit；其他原样
resolve_ref() {
    local ref="$1" repo="$2" pattern="$3" gh_repo branch=""
    case "${ref:-auto}" in
        auto|"") detect_latest_tag "$repo" "$pattern" ;;
        main|latest)
            gh_repo="$(printf '%s' "$repo" | sed -E 's|https://github.com/([^/]+)/([^/]+?)(\.git)?$|\1/\2|')"
            if command -v gh >/dev/null 2>&1 && [ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]; then
                branch="$(gh api "repos/${gh_repo}" --jq '.default_branch' 2>/dev/null || true)"
            fi
            # 默认分支名（main / master 因仓库而异；gh 不可用时 fallback git）
            [ -n "$branch" ] || branch="$(git ls-remote --symref "$repo" HEAD \
                | awk '/^ref:/ {print $2}' | sed 's|refs/heads/||')"
            echo "$branch"
            ;;
        *) echo "$ref" ;;
    esac
}

# checkout 上游仓库到指定 ref（兼容 tag / 分支 / sha）
sync_repo() {
    local dir="$1" repo="$2" ref="$3"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch --depth 1 origin "$ref" 2>/dev/null \
            || git -C "$dir" fetch --depth 1 origin tag "$ref"
        git -C "$dir" reset -q --hard   # 丢弃旧 patch 等本地修改
        git -C "$dir" checkout -q FETCH_HEAD
    else
        git clone --depth 1 -q "$repo" "$dir"
        git -C "$dir" fetch --depth 1 origin "$ref" 2>/dev/null \
            || git -C "$dir" fetch --depth 1 origin tag "$ref"
        git -C "$dir" checkout -q FETCH_HEAD
    fi
}

AGENT_VERSION="$(resolve_ref "${1:-}" https://github.com/nousresearch/hermes-agent.git '^v20[0-9]{2}\.' || true)"
WEBUI_VERSION="$(resolve_ref "${2:-}" https://github.com/nesquena/hermes-webui.git '^v0\.' || true)"
[ -n "$AGENT_VERSION" ] || { echo "!! 无法解析 agent ref（上游访问失败？网络/限流）" >&2; exit 1; }
[ -n "$WEBUI_VERSION" ] || { echo "!! 无法解析 webui ref（上游访问失败？网络/限流）" >&2; exit 1; }

# tag 模式判定（release）vs 分支/commit 模式
AGENT_IS_TAG=false; [[ "$AGENT_VERSION" =~ ^v20[0-9]{2}\. ]] && AGENT_IS_TAG=true
WEBUI_IS_TAG=false; [[ "$WEBUI_VERSION" =~ ^v0\. ]] && WEBUI_IS_TAG=true

# 基镜像 tag：非 release 模式基座用最新 release 镜像（无分支 tag）
BASE_IMAGE_TAG="$AGENT_VERSION"
$AGENT_IS_TAG || BASE_IMAGE_TAG="$(detect_latest_tag https://github.com/nousresearch/hermes-agent.git '^v20[0-9]{2}\.')"
# webui patch 版本：非 release 模式用 0.0.0（PEP 440 占位）
WEBUI_PATCH_VERSION="${WEBUI_VERSION#v}"
$WEBUI_IS_TAG || WEBUI_PATCH_VERSION="0.0.0"
# 非 release 模式源码与基镜像 pyproject 可能不一致 → 不 --frozen，构建期自动重 lock
UV_SYNC_FROZEN="--frozen"
$AGENT_IS_TAG || UV_SYNC_FROZEN=""

echo "== 解析：agent=${AGENT_VERSION} webui=${WEBUI_VERSION} (base=${BASE_IMAGE_TAG}) =="

mkdir -p temp
sync_repo temp/hermes https://github.com/nousresearch/hermes-agent.git "$AGENT_VERSION"
sync_repo temp/webui https://github.com/nesquena/hermes-webui.git "$WEBUI_VERSION"
bash docker/patch-webui-pyproject.sh temp/webui "$WEBUI_PATCH_VERSION"

# workspace 根（与镜像内 /opt 同构）
cat > temp/pyproject.toml <<'EOF'
[project]
name = "hermes-webui-all-in-one"
version = "0"
dependencies = [
    # extras 与官方 Dockerfile 一致
    "hermes-agent[all,messaging,otlp,anthropic,bedrock,azure-identity,hindsight,matrix]",
    "hermes-webui",
]

[tool.uv.sources]
hermes-agent = { workspace = true }
hermes-webui = { workspace = true }

[tool.uv.workspace]
members = ["hermes", "webui"]

[tool.uv]
package = false
EOF

cd temp && uv lock && cd ..

# 解析结果（供 build.sh / CI 使用）
cat > temp/versions.env <<EOF
AGENT_VERSION=${AGENT_VERSION}
WEBUI_VERSION=${WEBUI_VERSION}
BASE_IMAGE_TAG=${BASE_IMAGE_TAG}
WEBUI_PATCH_VERSION=${WEBUI_PATCH_VERSION}
UV_SYNC_FROZEN=${UV_SYNC_FROZEN}
EOF

echo "== temp/ 就绪：agent@${AGENT_VERSION} webui@${WEBUI_VERSION} =="
