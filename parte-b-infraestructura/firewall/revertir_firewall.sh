#!/usr/bin/env bash
# Retira el firewall del laboratorio (deja el host como estaba).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
if nft list table inet stark_fw >/dev/null 2>&1; then
    nft delete table inet stark_fw
    echo "[+] Tabla stark_fw eliminada."
else
    echo "[i] La tabla stark_fw no estaba cargada."
fi
