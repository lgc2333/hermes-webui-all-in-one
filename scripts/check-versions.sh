#!/usr/bin/env bash
# 对比 ghcr latest 镜像与上游 hermes-agent / hermes-webui 版本，输出 key=value 供 cron/agent 决策
# 用法: bash scripts/check-versions.sh
# 输出: AGENT_UP WEBUI_UP AGENT_IMG WEBUI_IMG DIFF(yes/no) 及镜像 digest
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="lgc2333/hermes-webui-all-in-one"
REG="https://ghcr.io/v2/${REPO}"
ACCEPT="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json"

# 1. 上游 latest release tag（gh 优先，fallback git ls-remote）
AGENT_UP=""
WEBUI_UP=""
if command -v gh >/dev/null 2>&1; then
  AGENT_UP=$(gh api repos/nousresearch/hermes-agent/releases/latest --jq .tag_name 2>/dev/null || true)
  WEBUI_UP=$(gh api repos/nesquena/hermes-webui/releases/latest --jq .tag_name 2>/dev/null || true)
fi
[ -n "$AGENT_UP" ] || AGENT_UP=$(git ls-remote --tags --refs https://github.com/nousresearch/hermes-agent.git | awk -F/ '{print $NF}' | grep -E '^v20[0-9]{2}\.' | sort -V | tail -1)
[ -n "$WEBUI_UP" ] || WEBUI_UP=$(git ls-remote --tags --refs https://github.com/nesquena/hermes-webui.git | awk -F/ '{print $NF}' | grep -E '^v0\.' | sort -V | tail -1)

# 2. ghcr latest digest（匿名 registry API）
TOKEN=$(curl -sf "https://ghcr.io/token?scope=repository:${REPO}:pull" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
get_digest() { # $1=tag
  curl -sf -D /tmp/hdr.$$ -o /dev/null -H "Authorization: Bearer $TOKEN" -H "Accept: ${ACCEPT}" "${REG}/manifests/$1" >/dev/null 2>&1 || return 1
  awk 'tolower($1)=="docker-content-digest:"{gsub("\r","");print $2}' /tmp/hdr.$$
}
LATEST_DIGEST=$(get_digest latest)

# 3. 从 combo tag（master-v<A>-v<W> / vX.Y.Z-v<A>-v<W>）中找与 latest 同 digest 的版本
AGENT_IMG=""
WEBUI_IMG=""
TAGS=$(curl -sf -H "Authorization: Bearer $TOKEN" "${REG}/tags/list" | python3 -c "import sys,json;print('\n'.join(json.load(sys.stdin)['tags']))")
for T in $TAGS; do
  case "$T" in
    master-v20[0-9][0-9].*|v[0-9]*.[0-9]*.[0-9]*-v20[0-9][0-9].*)
      D=$(get_digest "$T" || true)
      if [ -n "$D" ] && [ "$D" = "$LATEST_DIGEST" ]; then
        AGENT_IMG=$(echo "$T" | sed -E 's/^[^-]+-v(20[0-9]{2}\.[0-9.]+)-v0\..+$/v\1/')
        WEBUI_IMG=$(echo "$T" | sed -E 's/^[^-]+-v(20[0-9]{2}\.[0-9.]+)-(v0\..+)$/\2/')
        break
      fi
      ;;
  esac
done
rm -f /tmp/hdr.$$

DIFF=no
[ -n "$AGENT_IMG" ] && [ -n "$WEBUI_IMG" ] && { [ "$AGENT_IMG" != "$AGENT_UP" ] || [ "$WEBUI_IMG" != "$WEBUI_UP" ]; } && DIFF=yes
[ -n "$AGENT_IMG" ] || DIFF=unknown

cat <<EOF
AGENT_UP=${AGENT_UP}
WEBUI_UP=${WEBUI_UP}
AGENT_IMG=${AGENT_IMG:-unknown}
WEBUI_IMG=${WEBUI_IMG:-unknown}
LATEST_DIGEST=${LATEST_DIGEST}
DIFF=${DIFF}
EOF
