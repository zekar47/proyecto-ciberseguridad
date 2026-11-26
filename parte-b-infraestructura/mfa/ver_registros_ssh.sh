#!/usr/bin/env bash
# Resume los eventos de autenticacion SSH (exitos, fallos de contrasena y de codigo TOTP).
# Uso: sudo ./ver_registros_ssh.sh
set -uo pipefail
if [[ -r /var/log/auth.log ]]; then
    log="$(grep -E 'sshd|google_authenticator' /var/log/auth.log | grep -v ' sudo: ')"   # sin las lineas de sudo que solo mencionan sshd
else
    log="$(journalctl -u ssh -u sshd --no-pager -o short-iso 2>/dev/null)"
fi
echo "=== Resumen ==="
printf '%-45s %s\n' "Sesiones aceptadas (keyboard-interactive):" "$(grep -c 'Accepted keyboard-interactive' <<<"$log")"
printf '%-45s %s\n' "Codigos TOTP aceptados:" "$(grep -c 'Accepted google_authenticator' <<<"$log")"
printf '%-45s %s\n' "Codigos TOTP invalidos:" "$(grep -c 'Invalid verification code' <<<"$log")"
printf '%-45s %s\n' "Intentos de reutilizar un codigo TOTP:" "$(grep -c 'reuse a previously used' <<<"$log")"
printf '%-45s %s\n' "Fallos de autenticacion (PAM):" "$(grep -ci 'authentication failure' <<<"$log")"
printf '%-45s %s\n' "Intentos rechazados (Failed):" "$(grep -c 'Failed keyboard-interactive\|Failed password' <<<"$log")"
echo; echo "=== Ultimos eventos relevantes ==="
grep -E 'Accepted|Failed|Invalid verification|reuse a previously|Authentication failure' <<<"$log" \
    | sed -E 's/^([0-9T:-]{19})[^ ]* [^ ]+ /\1 /; s/ \("[^)]*\)//; s/ port [0-9]+ ssh2//' | tail -16
