#!/usr/bin/env bash
# Quita la configuracion STARK-MFA (vuelve a solo contrasena).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
sed -i '/# STARK-MFA inicio/,/# STARK-MFA fin/d' /etc/pam.d/sshd
rm -f /etc/ssh/sshd_config.d/10-stark-mfa.conf
sshd -t
if command -v systemctl >/dev/null && systemctl is-active --quiet ssh 2>/dev/null; then systemctl restart ssh; else pkill -HUP -x sshd || true; fi
echo "[+] MFA retirado."
