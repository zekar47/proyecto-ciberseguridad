#!/usr/bin/env bash
# Pruebas autorizadas desde la estacion de auditoria (Kali) contra SRV-STARK-01.
# Simula los segmentos agregando IPs de rol a la interfaz host-only de Kali.
#
# Uso: sudo ./pruebas_kali.sh <etiqueta>      (ej. antes | despues | cuarentena)
# Salida: carpeta resultados_<etiqueta>/ con la matriz y los escaneos Nmap.
set -uo pipefail

SRV="192.168.56.1"
IP_USUARIOS="192.168.56.110"   # representa VLAN 10
IP_ADMIN="192.168.56.130"      # representa VLAN 30
ETQ="${1:-prueba}"
OUT="resultados_${ETQ}"

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
for t in nmap nc; do command -v "$t" >/dev/null || { echo "Falta $t" >&2; exit 1; }; done

IFACE="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.56\./ {print $2; exit}')"
[[ -n "$IFACE" ]] || { echo "No hay interfaz en 192.168.56.0/24" >&2; exit 1; }
IP_PROPIA="$(ip -o -4 addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 | grep -v -e "$IP_USUARIOS" -e "$IP_ADMIN" | head -1)"

# IPs de rol (idempotente)
for ip in "$IP_USUARIOS" "$IP_ADMIN"; do
    ip addr show dev "$IFACE" | grep -q " $ip/" || ip addr add "$ip/24" dev "$IFACE"
done

mkdir -p "$OUT"
echo "Interfaz: $IFACE | Kali sin rol: $IP_PROPIA | Fecha: $(date -Is)" | tee "$OUT/matriz.txt"

prueba() {  # id  rol  ip_origen  puerto  esperado
    local id="$1" rol="$2" src="$3" port="$4" esperado="$5" res
    if timeout 4 nc -z -w 3 -s "$src" "$SRV" "$port" 2>/dev/null; then res="ABIERTO"; else res="BLOQUEADO"; fi
    local ok="OK"; [[ "$res" == "$esperado" ]] || ok="DIFERENTE"
    printf '%-4s %-15s %-15s %-6s %-10s esperado=%-10s %s\n' "$id" "$rol" "$src" "$port" "$res" "$esperado" "$ok" | tee -a "$OUT/matriz.txt"
}

echo "--- Matriz de conectividad (esperados = con firewall activo) ---" | tee -a "$OUT/matriz.txt"
prueba P1 Administracion "$IP_ADMIN"     22   ABIERTO
prueba P2 Usuarios       "$IP_USUARIOS"  22   BLOQUEADO
prueba P3 Usuarios       "$IP_USUARIOS"  445  ABIERTO
prueba P4 Administracion "$IP_ADMIN"     445  ABIERTO
prueba P5 Usuarios       "$IP_USUARIOS"  3306 BLOQUEADO
prueba P6 Administracion "$IP_ADMIN"     3306 BLOQUEADO
prueba P7 Sin-rol        "$IP_PROPIA"    22   BLOQUEADO
prueba P8 Sin-rol        "$IP_PROPIA"    445  BLOQUEADO

echo "--- Escaneos Nmap por rol (puertos del hallazgo del avance) ---"
for par in "usuarios:$IP_USUARIOS" "admin:$IP_ADMIN" "sinrol:$IP_PROPIA"; do
    rol="${par%%:*}"; src="${par#*:}"
    echo "[*] nmap desde $rol ($src)"
    nmap -Pn -sS -sV -n -e "$IFACE" -S "$src" -p 22,80,139,445,3306 "$SRV" -oN "$OUT/nmap_${rol}.txt" \
        | grep -E '^[0-9]+/tcp'
done

echo "[+] Resultados guardados en $OUT/"
