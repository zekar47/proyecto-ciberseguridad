#!/usr/bin/env bash
# SOLO LABORATORIO: simula la app autenticadora del telefono (Google Authenticator/Aegis).
# Calcula el codigo TOTP actual (RFC 6238, 30 s, 6 digitos) a partir del secreto enrolado.
# Uso: ./app_autenticadora.sh <carpeta_telefono> <usuario>
set -euo pipefail
oathtool --totp -b "$(cat "$1/$2.secreto")"
