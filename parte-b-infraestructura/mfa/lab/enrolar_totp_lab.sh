#!/usr/bin/env bash
# SOLO LABORATORIO: enrola a un usuario en TOTP sin intervencion y "entrega" el secreto a la app
# autenticadora simulada (en la practica real el usuario escanea el QR con su telefono).
# La salida enmascara el secreto, el QR y los codigos de emergencia para no publicarlos.
# Uso: sudo ./enrolar_totp_lab.sh <usuario> <carpeta_telefono>
set -euo pipefail
u="$1"; tel="$2"
su - "$u" -c "google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 5 -C -Q NONE" \
  | sed -E 's/(secret key is: )(.{4}).*/\1\2**********************  (enmascarado)/;
            s/(verification code for code 1 is )[0-9]+/\1****** (enmascarado)/;
            s/^( +)([0-9]{2})[0-9]{6}$/\1\2****** (enmascarado)/;
            s#(https://www.google.com/chart\S*|otpauth://\S*)#[URL del codigo QR omitida: contiene el secreto]#'
mkdir -p "$tel"; head -1 "/home/$u/.google_authenticator" > "$tel/$u.secreto"; chmod 600 "$tel/$u.secreto"
sed -n '6,10p' "/home/$u/.google_authenticator" > "$tel/$u.emergencia"; chmod 600 "$tel/$u.emergencia"
echo; echo "[lab] Secreto cargado en la app autenticadora simulada ($tel)."
