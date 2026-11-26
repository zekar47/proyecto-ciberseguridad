#!/usr/bin/env bash
# Aplica el firewall de SRV-STARK-01 (ejecutar en el host Arch Linux con sudo).
# Uso: sudo ./aplicar_firewall.sh [interfaz]
#   Si no se indica interfaz, se detecta la que tiene la IP 192.168.56.1.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_IP="192.168.56.1"

if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta con sudo: sudo $0 [interfaz]" >&2
    exit 1
fi

IFACE="${1:-$(ip -o -4 addr show | awk -v ip="$LAB_IP" '$4 ~ "^"ip"/" {print $2; exit}')}"
if [[ -z "$IFACE" ]]; then
    echo "No se encontro la interfaz con $LAB_IP. Arranca la VM de Kali o indica la interfaz." >&2
    exit 1
fi
echo "[*] Interfaz del laboratorio: $IFACE"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
sed "s/@LAB_IF@/$IFACE/g" "$DIR/stark_fw.nft" > "$TMP"

echo "[*] Validando sintaxis (nft -c)..."
nft -c -f "$TMP"
echo "[*] Aplicando reglas..."
nft -f "$TMP"
echo "[+] Firewall aplicado. Reglas activas:"
nft list table inet stark_fw
