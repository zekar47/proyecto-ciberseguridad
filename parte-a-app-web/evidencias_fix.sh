#!/usr/bin/env bash
# Evidencias de las Actividades 4 (validación) y 5 (registros) con la versión CORREGIDA.
# Uso:  cd ~/Desktop/vulnerable && bash evidencias_fix.sh
set -u
cd "$(dirname "$0")"
RAIZ="$(pwd)"; EV="$RAIZ/evidencias"; mkdir -p "$EV/capturas_fix"
source .venv/bin/activate
titulo() { printf '\n==================== %s ====================\n' "$1"; }
cmd() { printf '\n$ %s\n' "$*"; eval "$@"; }

# Respaldo de las evidencias de la versión vulnerable (para el commit v1-vulnerable)
if [ ! -d _publicar/evidencias_antes ]; then
  mkdir -p _publicar && cp -a evidencias _publicar/evidencias_antes
  rm -rf _publicar/evidencias_antes/capturas_fix
fi

mkdir -p logs && [ -f logs/app.log ] && mv logs/app.log "logs/app_$(date +%H%M%S)_anterior.log"
python app.py > "$EV/12_app_fix_salida.txt" 2>&1 &
APP_PID=$!
for i in $(seq 1 20); do curl -s http://127.0.0.1:5050/salud | grep -q stark-portal && break; sleep 1; done

{
titulo "A4. Versión corregida en ejecución"
cat "$EV/12_app_fix_salida.txt"
cmd "grep -n 'FIX-' app.py templates/*.html | head -20"
titulo "A4. Repetición de las pruebas automatizadas"
cmd "python exploits/demo_vulns.py"
} 2>&1 | tee "$EV/13_demo_fix.txt"

{
titulo "A4. Repetición de las pruebas manuales con curl"
J=/tmp/stark_j.txt; rm -f $J
echo; echo "# SQLi: evasión de autenticación (usuario = ana.ti' --)"
cmd "curl -s -c $J -o /dev/null -w 'HTTP %{http_code} %{redirect_url}\n' --data-urlencode \"username=ana.ti' --\" --data-urlencode 'password=x' http://127.0.0.1:5050/login"
cmd "curl -s -c $J -o /dev/null -d 'username=sofia.consulta&password=Consulta*26' http://127.0.0.1:5050/login"
echo; echo "# SQLi: UNION en /buscar"
cmd "curl -s -b $J -G --data-urlencode \"q=zzz' UNION SELECT username, password, rol FROM usuarios --\" http://127.0.0.1:5050/buscar | grep -c 'TI#Stark2026'"
echo; echo "# XSS reflejado: el payload ahora aparece escapado"
cmd "curl -s -b $J -G --data-urlencode \"q=<script>alert('XSS-Stark')</script>\" http://127.0.0.1:5050/buscar | grep -n 'Resultados para'"
echo; echo "# Cabeceras de seguridad (CSP)"
cmd "curl -s -b $J -D - -o /dev/null http://127.0.0.1:5050/buscar | grep -iE 'content-security|x-content-type|x-frame'"
echo; echo "# IDOR/BOLA: luis.oper (id 2) pide recursos ajenos"
rm -f $J
cmd "curl -s -c $J -D - -o /dev/null -d 'username=luis.oper&password=Turno1!2026' http://127.0.0.1:5050/login | grep -i set-cookie"
for id in 2 4 1; do cmd "curl -s -b $J -w '  [HTTP %{http_code}]\n' http://127.0.0.1:5050/api/ordenes/$id"; done
cmd "curl -s -b $J -o /dev/null -w 'GET /perfil/4 -> HTTP %{http_code}\n' http://127.0.0.1:5050/perfil/4"
echo; echo "# Acceso legítimo de administración: ana.ti (stark_ti) sí puede ver la orden 4"
rm -f $J
cmd "curl -s -c $J -o /dev/null -d 'username=ana.ti&password=TI%23Stark2026' http://127.0.0.1:5050/login"
cmd "curl -s -b $J -w '  [HTTP %{http_code}]\n' http://127.0.0.1:5050/api/ordenes/4"
rm -f $J
} 2>&1 | tee "$EV/14_curl_fix.txt"

titulo "A4. Capturas del navegador (versión corregida)"
CAPTURAS_DIR=capturas_fix python tools/capturas_vulns.py 2>&1 | tee "$EV/15_capturas_fix.txt"

# --- OWASP ZAP después de las correcciones ---
ZAPSH="$(ls -d .tools/ZAP_*/zap.sh 2>/dev/null | tail -1)"
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
JAVA="$(command -v java 2>/dev/null)"; "$JAVA" -version >/dev/null 2>&1 || JAVA="$("$BREW" --prefix openjdk)/bin/java"
export PATH="$(dirname "$JAVA"):$PATH"
if [ -n "$ZAPSH" ]; then
  titulo "A4. OWASP ZAP después de las correcciones"
  bash "$ZAPSH" -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true \
       -config start.checkForUpdates=false > "$EV/zap_daemon_despues.log" 2>&1 &
  ZAP_PID=$!
  for i in $(seq 1 120); do curl -s http://127.0.0.1:8090/JSON/core/view/version/ >/dev/null 2>&1 && break; sleep 2; done
  python tools/capturas.py --zap http://127.0.0.1:8090 > /dev/null
  ZAP_SUFIJO=despues python tools/zap_scan.py 2>&1 | tee "$EV/16_zap_despues.txt"
  python - <<'EOF'
from pathlib import Path
from playwright.sync_api import sync_playwright
ev = Path("evidencias"); rep = (ev / "zap-reporte-despues.html").resolve()
if rep.exists():
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, channel="chrome")
        pg = b.new_page(viewport={"width": 1280, "height": 900})
        pg.goto(rep.as_uri())
        pg.screenshot(path=str(ev / "capturas_fix" / "zap_reporte_despues.png"))
        b.close()
    print("  captura -> evidencias/capturas_fix/zap_reporte_despues.png")
EOF
  kill $ZAP_PID 2>/dev/null
fi

# --- Actividad 5: eventos controlados y análisis de registros ---
cp logs/app.log logs/app_actividad4.log
: > logs/app.log
{
titulo "A5. Generación de eventos controlados"
cmd "python tools/eventos_controlados.py"
} 2>&1 | tee "$EV/17_eventos_controlados.txt"
{
titulo "A5. Eventos de seguridad registrados (WARNING)"
cmd "grep WARNING logs/app.log"
} 2>&1 | tee "$EV/18_log_eventos.txt"
{
titulo "A5. Análisis de registros"
cmd "python tools/analizar_logs.py"
} 2>&1 | tee "$EV/19_analisis_logs.txt"
cp logs/app.log "$EV/app_actividad5.log"

kill $APP_PID 2>/dev/null
titulo "LISTO"
ls -1 "$EV/capturas_fix"
