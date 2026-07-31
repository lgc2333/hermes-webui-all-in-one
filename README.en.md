**English** | [简体中文](README.md)

# hermes-webui-all-in-one

One image for your self-hosted [Hermes Agent](https://hermes-agent.nousresearch.com/) all-in-one stack: the agent + [Hermes WebUI](https://github.com/nesquena/hermes-webui) (third-party community project) browser interface + Remote Gateway. Derived from the official `nousresearch/hermes-agent` image; webui runs as an s6 service sharing one venv (uv workspace) with the agent.

## Why this project

Each of webui's built-in deployment options has its own problems:

- **webui single-container**: only port 8787 — the dashboard (9119) can't be exposed, and the 9119 bridge that the desktop app (Hermes Desktop) needs simply doesn't exist in webui
- **agent + webui multi-container**: webui runs another copy of hermes inside its own container, so the two environments (venv, system deps) diverge and stdio MCP servers may fail to start; on top of that, webui's venv has to reinstall all of hermes's dependencies
- **webui gateway bridge mode**: partially broken, poor experience — not a viable way to unify both sides

This project merges agent and webui into a single uv workspace inside one image:

- **Unified environment**: agent and webui share `/opt/.venv`, dependencies installed once, no more two divergent environments
- **All three ports in one**: webui (8787) / dashboard (9119) / gateway (8642) started with a single compose file; desktop connects straight to 9119
- **Derivative maintenance**: official image as the base plus a derived layer — no fork, no upstream source changes; rebuild directly on upstream releases

## Features

- **Single image, single venv**: webui is patched into a virtual non-installed `[project]` member of the uv workspace at build time, unified `/opt/.venv`, zero changes to the base image
- **All three ports in one**: webui `8787` / dashboard `9119` / gateway API `8642`
- **s6 service orchestration** + HEALTHCHECK probing both webui and gateway
- **Image signing** (cosign), combo tags `<this-project>-<agent>-<webui>` pin upstream versions
- **Fully automated CI**: builds and pushes on `v*` tags, PRs only validate the build

## Quick start

```bash
cp .env.example .env   # API_SERVER_KEY is required
docker compose up -d
```

| Port | Service | Description |
|------|---------|-------------|
| 8787 | Hermes WebUI | Browser chat interface |
| 9119 | Dashboard | Remote connection for Hermes Desktop (basic auth / oauth) |
| 8642 | Gateway API | Agent HTTP API (webui bridge, requires API_SERVER_KEY) |

See `.env.example` for all environment variables; for the rest, refer to the [Hermes Agent docs](https://hermes-agent.nousresearch.com/docs) and the [WebUI configuration guide](https://github.com/nesquena/hermes-webui#configuration--access).

**root/sudo access**: the image ships without sudo and no usable passwords. To get root inside the container, create your own sudoers file and mount it in:

1. Create the sudoers file on the host (username hermes is fixed; uid varies with HERMES_UID — no need to adjust):

```bash
echo 'hermes ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee ./sudoers-hermes
sudo chown root:root ./sudoers-hermes && sudo chmod 440 ./sudoers-hermes
```

The file must be owned by root with mode 0440, otherwise sudo silently ignores it — no error, no effect.

2. Mount it in compose:

```yaml
volumes:
  - ./data:/opt/data
  - ./sudoers-hermes:/etc/sudoers.d/hermes:ro
```

Restart, then `sudo <cmd>` works passwordless inside the container. Note: passwordless sudo has security implications — weigh them yourself.

## Build from source

```bash
bash docker/sync-sources.sh <agent-ref> <webui-ref>   # stage temp/ build assets
docker build -t hermes-webui-all-in-one .
```

## Acknowledgements

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — the agent itself and the base image
- [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) — the WebUI

## Sponsorship

**[Sponsor me](https://lgck.cc/sponsor)**

Thank you for your support! Your sponsorship keeps me creating!

## Contact

- QQ: 3076823485
- QQ Group: [168603371](https://qm.qq.com/q/EikuZ5sP4G)
- Telegram: [@lgc2333](https://t.me/lgc2333)
- Email: <lgc2333@126.com>

## License

[MIT](LICENSE)
