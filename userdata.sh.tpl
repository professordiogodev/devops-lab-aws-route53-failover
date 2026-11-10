#!/bin/bash
# First boot: install Clippy on port 80. APP_VERSION says which server answers (primary or secondary).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y python3-venv git
id clippy >/dev/null 2>&1 || useradd --system --home /opt/clippy --shell /usr/sbin/nologin clippy
git clone --branch v0.2.0 --depth 1 https://github.com/professordiogodev/clippy /opt/clippy
python3 -m venv /opt/clippy/.venv && /opt/clippy/.venv/bin/pip install -q -r /opt/clippy/requirements.txt
chown -R clippy:clippy /opt/clippy
cat > /etc/systemd/system/clippy.service <<UNIT
[Unit]
Description=Clippy
After=network-online.target
[Service]
User=clippy
WorkingDirectory=/opt/clippy
Environment=APP_VERSION=ROLE_NAME
ExecStart=/opt/clippy/.venv/bin/uvicorn api.main:app --host 0.0.0.0 --port 80
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now clippy
