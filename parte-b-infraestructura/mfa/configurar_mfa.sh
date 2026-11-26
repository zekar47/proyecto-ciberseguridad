#!/usr/bin/env bash
# Stark - Parte B, Opcion D: exige un segundo factor (TOTP) en SSH al perfil privilegiado stark_ti.
# Ejecutar en SRV-STARK-01 (Ubuntu/Debian) con sudo. Hace respaldo de los archivos que modifica.
# Uso: sudo ./configurar_mfa.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }

PAM=/etc/pam.d/sshd
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-stark-mfa.conf
MARCA="# STARK-MFA"
FECHA="$(date +%Y%m%d-%H%M%S)"

# 1) Modulo TOTP
if ! ls /lib/*/security/pam_google_authenticator.so /usr/lib/*/security/pam_google_authenticator.so >/dev/null 2>&1; then
    echo "[*] Instalando libpam-google-authenticator..."
    apt-get update -qq && apt-get install -y -qq libpam-google-authenticator
fi

# 2) PAM: despues de la contrasena (common-auth), pedir el codigo solo a stark_ti
if ! grep -q "$MARCA" "$PAM"; then
    cp -a "$PAM" "$PAM.bak-$FECHA"
    sed -i "/^@include common-auth/a\\
$MARCA inicio: segundo factor (TOTP) solo para el grupo privilegiado stark_ti\\
auth [success=1 default=ignore] pam_succeed_if.so user notingroup stark_ti quiet\\
auth required pam_google_authenticator.so\\
$MARCA fin" "$PAM"
    echo "[+] PAM actualizado (respaldo: $PAM.bak-$FECHA)"
else
    echo "[i] PAM ya tenia la configuracion STARK-MFA"
fi

# 3) SSH: solo keyboard-interactive (contrasena + codigo pasan por PAM)
cat > "$SSHD_DROPIN" <<'CONF'
# STARK-MFA: la autenticacion pasa por PAM (contrasena + codigo TOTP)
UsePAM yes
KbdInteractiveAuthentication yes
PasswordAuthentication no
AuthenticationMethods keyboard-interactive
CONF
# En sshd gana el PRIMER valor leido: avisar si un archivo que se lee antes (orden alfabetico) contradice este.
for f in /etc/ssh/sshd_config.d/*.conf; do
    [[ "$f" < "$SSHD_DROPIN" ]] || continue
    if grep -qiE '^\s*(PasswordAuthentication|KbdInteractiveAuthentication|AuthenticationMethods)' "$f"; then
        echo "[!] $f tambien define opciones de autenticacion; revisa que no contradiga $SSHD_DROPIN"
    fi
done

echo "[*] Validando configuracion de sshd (sshd -t)..."
sshd -t
if command -v systemctl >/dev/null && systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
else
    pkill -HUP -x sshd || true
fi
echo "[+] MFA activo para stark_ti. Antes de cerrar esta sesion, prueba en OTRA terminal que puedes entrar."
