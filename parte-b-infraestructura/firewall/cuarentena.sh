#!/usr/bin/env bash
# Contencion de incidentes: aisla (o libera) un equipo del servidor.
# Uso:
#   sudo ./cuarentena.sh agregar 192.168.56.110 [duracion, ej. 2h]
#   sudo ./cuarentena.sh quitar  192.168.56.110
#   sudo ./cuarentena.sh listar
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }

accion="${1:-listar}"
ip="${2:-}"
dur="${3:-}"

valida_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "IP invalida: $1" >&2; exit 1; }
}

case "$accion" in
    agregar)
        valida_ip "$ip"
        if [[ -n "$dur" ]]; then
            nft add element inet stark_fw cuarentena "{ $ip timeout $dur }"
        else
            nft add element inet stark_fw cuarentena "{ $ip }"
        fi
        # Corta tambien las conexiones ya abiertas desde ese equipo (si conntrack esta instalado).
        command -v conntrack >/dev/null && conntrack -D -s "$ip" >/dev/null 2>&1 || true
        logger -t stark-ir "CUARENTENA aplicada a $ip ${dur:+por $dur}"
        echo "[+] $ip en cuarentena."
        ;;
    quitar)
        valida_ip "$ip"
        nft delete element inet stark_fw cuarentena "{ $ip }"
        logger -t stark-ir "CUARENTENA retirada a $ip"
        echo "[+] $ip liberado."
        ;;
    listar)
        nft list set inet stark_fw cuarentena
        ;;
    *)
        echo "Uso: $0 {agregar|quitar|listar} [ip] [duracion]" >&2; exit 1;;
esac
