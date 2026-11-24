#!/usr/bin/env bash
# Publica la Parte A en el repo del equipo con dos versiones comprobables:
#   1) main  <- versión VULNERABLE + evidencias "antes"      (tag v1-vulnerable)
#   2) rama fix/vulnerabilidades <- versión CORREGIDA + evidencias "después" (tag v2-segura) + Pull Request
# Uso:  cd ~/Desktop/vulnerable && bash publicar_git.sh
set -euo pipefail
cd "$(dirname "$0")"
SRC="$(pwd)"
REPO_URL="${REPO_URL:-https://github.com/zekar47/proyecto-ciberseguridad.git}"
DEST="${DEST:-$HOME/Desktop/proyecto-ciberseguridad}"
CARPETA="parte-a-app-web"
SESION="https://claude.ai/code/session_01BechHsJfRs9dqfFPB9UZxJ"

[ -d "$SRC/_publicar/v1_codigo" ] || { echo "Falta _publicar/v1_codigo"; exit 1; }
[ -d "$SRC/_publicar/evidencias_antes" ] || { echo "Primero corre: bash evidencias_fix.sh"; exit 1; }
git config user.name >/dev/null || { echo "Configura git: git config --global user.name 'Tu Nombre'"; exit 1; }

# Archivos que nunca se suben
SYNC=(python3 "$SRC/tools/sincronizar.py")
EXCL=(--exclude .venv --exclude .tools --exclude logs --exclude stark.db --exclude __pycache__
      --exclude _publicar --exclude '*.docx' --exclude .DS_Store --exclude '*.pyc')
EXCL_EVID=(--exclude 'zap_daemon*.log' --exclude '05a_zap_instalacion.txt' --exclude .DS_Store)

echo "==> Clonando / actualizando $REPO_URL"
[ -d "$DEST/.git" ] || git clone "$REPO_URL" "$DEST"
cd "$DEST"
git fetch origin --tags
git checkout main
git pull --ff-only origin main

# ---------------------------------------------------------------- v1
if git rev-parse -q --verify refs/tags/v1-vulnerable >/dev/null; then
  echo "==> v1-vulnerable ya existe; se omite"
else
  echo "==> Commit 1: versión vulnerable"
  mkdir -p "$CARPETA"
  "${SYNC[@]}" "$SRC/_publicar/v1_codigo" "$CARPETA" "${EXCL[@]}" --exclude evidencias
  "${SYNC[@]}" "$SRC/_publicar/evidencias_antes" "$CARPETA/evidencias" "${EXCL_EVID[@]}"
  if ! grep -q "$CARPETA" README.md 2>/dev/null; then
    cat >> README.md <<EOF

Proyecto final de Ciberseguridad (Tecmilenio) · Organización ficticia: Stark Manufactura.

- [\`$CARPETA/\`]($CARPETA/): Parte A, aplicación web de laboratorio (SQL Injection, XSS, IDOR/BOLA).
  - Tag \`v1-vulnerable\`: versión vulnerable. Tag \`v2-segura\`: versión corregida (rama \`fix/vulnerabilidades\`).
EOF
  fi
  git add -A
  git commit -q -F - <<EOF
Parte A: aplicación vulnerable de laboratorio (SQLi, XSS, IDOR/BOLA)

App Flask "Stark Manufactura · Portal interno" intencionalmente vulnerable:
- VULN-1 SQL Injection en /login y /buscar (consultas concatenadas)
- VULN-2 XSS reflejado (/buscar) y almacenado (/comentarios) por |safe
- VULN-3 IDOR/BOLA en /perfil/<id> y /api/ordenes/<id> (sin autorización)

Incluye scripts de prueba, configuración de OWASP ZAP y evidencias de las
Actividades 1 y 2. Datos ficticios; solo escucha en 127.0.0.1.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: $SESION
EOF
  git tag -a v1-vulnerable -m "Versión vulnerable (Actividades 1 y 2)"
  git push origin main
  git push origin v1-vulnerable
fi

# ---------------------------------------------------------------- v2
if git rev-parse -q --verify refs/tags/v2-segura >/dev/null; then
  echo "==> v2-segura ya existe; se omite"
else
  echo "==> Commit 2: correcciones en la rama fix/vulnerabilidades"
  git checkout -B fix/vulnerabilidades main
  "${SYNC[@]}" "$SRC" "$CARPETA" "${EXCL[@]}" --exclude evidencias
  "${SYNC[@]}" "$SRC/evidencias" "$CARPETA/evidencias" "${EXCL_EVID[@]}"
  git add -A
  git commit -q -F - <<EOF
Fix: corrige SQL Injection, XSS e IDOR/BOLA

- FIX-1 Consultas SQL parametrizadas en /login y /buscar; contraseñas con
  hash (werkzeug.security) y mensajes de error genéricos
- FIX-2 Se elimina |safe (escapado automático de Jinja2), Content-Security-Policy
  estricta, CSS externo, cookie HttpOnly + SameSite=Lax y límites de longitud
- FIX-3 Validación de autorización en /perfil/<id> y /api/ordenes/<id>:
  solo el propietario o stark_ti; si no, 403
- Registro de eventos de seguridad (login_fallido, acceso_denegado,
  entrada_sospechosa) y scripts de eventos controlados y análisis de logs

Evidencias de las Actividades 4 y 5: las 7 pruebas pasan de VULNERABLE a
PROTEGIDO y ZAP ya no reporta alertas de riesgo alto.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: $SESION
EOF
  git tag -a v2-segura -m "Versión corregida (Actividades 3, 4 y 5)"
  git push -u origin fix/vulnerabilidades
  git push origin v2-segura
fi

# ---------------------------------------------------------------- Pull Request
CUERPO="$(mktemp)"
cat > "$CUERPO" <<EOF
## Correcciones de la Parte A

| | Vulnerabilidad (\`v1-vulnerable\`) | Corrección (\`v2-segura\`) |
|---|---|---|
| FIX-1 | SQL Injection en \`/login\` y \`/buscar\` | Consultas parametrizadas, hash de contraseñas, errores genéricos |
| FIX-2 | XSS reflejado y almacenado | Sin \`\|safe\`, Content-Security-Policy, cookie HttpOnly/SameSite |
| FIX-3 | IDOR/BOLA en \`/perfil/<id>\` y \`/api/ordenes/<id>\` | Validación de propietario o perfil \`stark_ti\`; 403 si no |

### Cómo comprobarlo
\`\`\`bash
git checkout v1-vulnerable && cd $CARPETA && python app.py   # en otra terminal: python exploits/demo_vulns.py -> VULNERABLE
git checkout v2-segura     && cd $CARPETA && python app.py   # python exploits/demo_vulns.py -> PROTEGIDO
\`\`\`

Evidencias: \`$CARPETA/evidencias/\` (\`capturas_vulns/\` = antes, \`capturas_fix/\` = después, \`zap-reporte-antes.html\` / \`zap-reporte-despues.html\`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

$SESION
EOF
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh pr view fix/vulnerabilidades >/dev/null 2>&1 || \
    gh pr create --repo zekar47/proyecto-ciberseguridad --base main --head fix/vulnerabilidades \
      --title "Fix: corrige SQL Injection, XSS e IDOR/BOLA (Parte A)" --body-file "$CUERPO"
  gh pr view fix/vulnerabilidades --repo zekar47/proyecto-ciberseguridad --json url -q .url
else
  cp "$CUERPO" "$SRC/_publicar/descripcion_pr.md"
  echo
  echo "No encontré GitHub CLI (gh) con sesión iniciada. Abre este enlace para crear el Pull Request:"
  echo "  https://github.com/zekar47/proyecto-ciberseguridad/compare/main...fix/vulnerabilidades?expand=1"
  echo "La descripción quedó en _publicar/descripcion_pr.md"
fi
rm -f "$CUERPO"
git checkout -q main
echo
echo "==> Listo. Repo local en: $DEST"
git log --oneline --decorate --all | head -5
