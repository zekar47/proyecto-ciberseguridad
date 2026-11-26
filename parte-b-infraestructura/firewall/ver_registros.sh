#!/usr/bin/env bash
# Resume los eventos del firewall registrados en el journal del kernel.
# Uso: sudo ./ver_registros.sh ["30 min ago"]
set -euo pipefail
desde="${1:-1 hour ago}"

eventos="$(journalctl -k --since "$desde" --no-pager -o short-iso 2>/dev/null | grep 'STARK-FW' || true)"
# Respaldo: si journald no tiene los mensajes del kernel, se leen con dmesg.
if [[ -z "$eventos" ]]; then
    eventos="$(dmesg 2>/dev/null | grep 'STARK-FW' || true)"
fi

if [[ -z "$eventos" ]]; then
    echo "Sin eventos STARK-FW desde: $desde"; exit 0
fi

echo "=== Eventos por tipo ==="
grep -o 'STARK-FW [A-Z-]*' <<<"$eventos" | sort | uniq -c | sort -rn

echo; echo "=== Origen -> puerto destino (top 15) ==="
sed -n 's/.*\(STARK-FW [A-Z-]*\):.*SRC=\([0-9.]*\).*DPT=\([0-9]*\).*/\1  \2 -> \3/p' <<<"$eventos" \
    | sort | uniq -c | sort -rn | head -15

echo; echo "=== Ultimos 10 eventos (tiempo | regla | origen -> destino:puerto) ==="
tail -10 <<<"$eventos" | sed -n 's/^\(.\{0,26\}\).*\(STARK-FW [A-Z-]*\):.*SRC=\([0-9.]*\) DST=\([0-9.]*\).*DPT=\([0-9]*\).*/\1 | \2 | \3 -> \4:\5/p'

echo; echo "=== Contadores de reglas ==="
nft list chain inet stark_fw input | grep -E 'counter packets [1-9]' || echo "(sin coincidencias)"
