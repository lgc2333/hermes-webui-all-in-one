**简体中文** | [English](README.en.md)

# hermes-webui-all-in-one

一个镜像搞定 [Hermes Agent](https://hermes-agent.nousresearch.com/) 自托管全家桶：agent + [Hermes WebUI](https://github.com/nesquena/hermes-webui)（第三方社区项目）浏览器界面 + Remote Gateway。基于官方 `nousresearch/hermes-agent` 镜像派生，webui 注册为 s6 服务，与 agent 共享同一 venv（uv workspace）。

## 为什么做这个项目

webui 自带的部署方案各有各的问题：

- **webui 单容器**：只有 8787，暴露不了 dashboard（9119）——桌面端（Hermes Desktop）要连的 9119 桥接在 webui 里并不存在
- **agent + webui 多容器**：webui 在自己容器里另跑一份 hermes，两边环境（venv、系统依赖）不统一，stdio MCP 有的可能起不来；而且 webui 的 venv 还得把 hermes 的依赖重新装一遍
- **webui 的 gateway 桥模式**：部分功能残废，体验不够好，不能靠它统一两侧

这个项目把 agent 和 webui 并成一个 uv workspace、合成一个镜像：

- **环境统一**：agent 与 webui 共用 `/opt/.venv`，依赖一次装齐，不再有两套环境割裂
- **三端口一体**：webui（8787）/ dashboard（9119）/ gateway（8642）一条 compose 全起，桌面端直接连 9119
- **派生式维护**：官方镜像为基座加派生层，不 fork 不改上游源码，上游发版直接重建

## 特性

- **单镜像单 venv**：构建期将 webui patch 为 uv workspace 非安装 member，统一 `/opt/.venv`，基镜像零改动
- **三端口一体**：webui `8787` / dashboard `9119` / gateway API `8642`
- **s6 服务编排** + HEALTHCHECK 双探活（webui + gateway）
- **镜像签名**（cosign），组合标签 `<本项目>-<agent>-<webui>` 标识上游版本
- **CI 全自动**：push `v*` tag 构建推送，PR 仅验证构建

## 快速开始

```bash
cp .env.example .env   # 必填 API_SERVER_KEY
docker compose up -d
```

| 端口 | 服务 | 说明 |
|------|------|------|
| 8787 | Hermes WebUI | 浏览器聊天界面 |
| 9119 | Dashboard | Hermes Desktop 远程连接（basic auth / oauth） |
| 8642 | Gateway API | agent HTTP API（webui 桥接，需 API_SERVER_KEY） |

环境变量详见 `.env.example`，其余配置项建议查阅 [Hermes Agent 文档](https://hermes-agent.nousresearch.com/docs) 与 [WebUI 配置说明](https://github.com/nesquena/hermes-webui#configuration--access)。

**root/sudo 权限**：镜像默认无 sudo、无可用密码。如需容器内提权，自行创建 sudoers 文件并挂载：

1. 宿主机创建 sudoers 文件（用户名 hermes 固定；uid 随 HERMES_UID 变化，无需改动）：

```bash
echo 'hermes ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee ./sudoers-hermes
sudo chown root:root ./sudoers-hermes && sudo chmod 440 ./sudoers-hermes
```

文件需属主 root 且权限 0440，否则 sudo 会静默忽略，不报错也不生效。

2. compose volumes 挂载：

```yaml
volumes:
  - ./data:/opt/data
  - ./sudoers-hermes:/etc/sudoers.d/hermes:ro
```

重启后容器内 `sudo <命令>` 即可免密执行。注意：免密 sudo 有安全风险，请自行权衡。

## 手动构建

```bash
bash docker/sync-sources.sh <agent-ref> <webui-ref>   # 生成 temp/ 构建素材
docker build -t hermes-webui-all-in-one .
```

## 致谢

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — agent 本体与基镜像
- [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) — WebUI

## 赞助

**[赞助我](https://lgck.cc/sponsor)**

感谢大家的赞助！你们的赞助将是我继续创作的动力！

## 联系

- QQ：3076823485
- QQ群：[168603371](https://qm.qq.com/q/EikuZ5sP4G)
- Telegram：[@lgc2333](https://t.me/lgc2333)
- 邮箱：<lgc2333@126.com>

## License

[MIT](LICENSE)
