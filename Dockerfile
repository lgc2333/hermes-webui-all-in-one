# hermes-webui-all-in-one — 单镜像 + 单 venv（uv workspace）
# 基镜像 /opt/hermes 原样保留；/opt 为 workspace 根，/opt/.venv 为唯一 venv。
# AGENT_VERSION = 基镜像 tag（main 模式由 sync-sources.sh 解析为最新 release tag）；
# UV_SYNC_FROZEN = main 模式置空（源码与基镜像 pyproject 可能不一致，构建期重 lock）。
ARG AGENT_VERSION=v2026.7.30
ARG WEBUI_VERSION=v0.52.106
FROM nousresearch/hermes-agent:${AGENT_VERSION}

# ARG 作用域：FROM 前声明的只对 FROM 生效，此处重新声明
ARG WEBUI_VERSION=v0.52.106
ARG UV_SYNC_FROZEN=--frozen
USER root

# 基镜像无 sudo，补装；sudoers 由部署者自行挂载（见 README「root/sudo 权限」）
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends sudo && \
    rm -rf /var/lib/apt/lists/*

# workspace 素材（temp/ 由 docker/sync-sources.sh 生成，不入 git）
COPY temp/pyproject.toml /opt/pyproject.toml
COPY temp/uv.lock /opt/uv.lock
COPY --chown=hermes:hermes temp/webui /opt/webui

# webui 非安装包：构建期 patch 出 virtual [project] 表（workspace member，不安装）
COPY docker/patch-webui-pyproject.sh /tmp/patch-webui-pyproject.sh
RUN bash /tmp/patch-webui-pyproject.sh /opt/webui "${WEBUI_VERSION}" && rm /tmp/patch-webui-pyproject.sh

# 统一 venv（基镜像 /opt/hermes/.venv 不动；main 模式 UV_SYNC_FROZEN 为空；
# PRETEND_VERSION 供 webui master 模式（dynamic 版本 + 镜像内无 .git）构建用；
# agent 版本静态，不受影响）
# --no-cache：wheel 缓存不落镜像（uv sync 层约减半）
ENV UV_PROJECT_ENVIRONMENT=/opt/.venv
RUN cd /opt && SETUPTOOLS_SCM_PRETEND_VERSION="${WEBUI_VERSION}" uv sync --no-cache ${UV_SYNC_FROZEN}

# 删除基镜像旧 venv，软链到统一 venv：基镜像脚本硬编码引用
# /opt/hermes/.venv（stage2-hook/02-reconcile/dashboard/shims），
# symlink 让它们自动解析到 /opt/.venv，无需 patch 任何基镜像文件
RUN rm -rf /opt/hermes/.venv && ln -s /opt/.venv /opt/hermes/.venv

# 自检 + 版本烘焙（镜像内无 .git；含 symlink venv 验证）
RUN /opt/.venv/bin/python -c "import hermes_cli" && \
    /opt/hermes/.venv/bin/python -c "import os, sys; assert os.path.realpath(sys.prefix) == '/opt/.venv', sys.prefix" && \
    cd /opt/webui && /opt/.venv/bin/python -c "import api"
RUN echo "__version__ = '${WEBUI_VERSION}'" > /opt/webui/api/_version.py && chown hermes:hermes /opt/webui/api/_version.py

# 统一 venv 优先（s6 服务与 stdio hermes 子进程都走它）
ENV PATH="/opt/.venv/bin:${PATH}"

# s6 服务：hermes-webui（dashboard 用基镜像 slot，gateway 走容器主程序）
COPY docker/s6-rc.d/hermes-webui/ /etc/s6-overlay/s6-rc.d/hermes-webui/
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/hermes-webui

EXPOSE 8787 9119 8642

# 健康检查：webui + gateway API 双探活
HEALTHCHECK --interval=30s --timeout=8s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8787/health >/dev/null 2>&1 && curl -fsS http://127.0.0.1:8642/health >/dev/null 2>&1 || exit 1
