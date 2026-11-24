#!/usr/bin/env bash
# Genera las evidencias de la Actividad 1 (preparación del entorno) en macOS.
# Uso:  cd ~/vulnerable && bash evidencias.sh
set -u
cd "$(dirname "$0")"
RAIZ="$(pwd)"
EV="$RAIZ/evidencias"
mkdir -p "$EV/capturas"

titulo() { printf '\n==================== %s ====================\n' "$1"; }
cmd() { printf '\n$ %s\n' "$*"; eval "$@"; }

{
titulo "1. Entorno local"
cmd "sw_vers"
cmd "uname -m"
[ -d .venv ] || python3 -m venv .venv
source .venv/bin/activate
cmd "which python"
cmd "python --version"
} 2>&1 | tee "$EV/01_entorno.txt"

source .venv/bin/activate
{
titulo "2. Dependencias"
cmd "pip install -q -r requirements.txt playwright"
cmd "pip show flask requests playwright | grep -E '^(Name|Version)'"
} 2>&1 | tee "$EV/02_dependencias.txt"

# OWASP ZAP se ejecuta aparte con evidencias_zap.sh
ZAP_OK=0

# --- Aplicación ----------------------------------------------------------------
titulo "4. Ejecución de la aplicación"
echo '$ python app.py'
python app.py > "$EV/03_app_salida.txt" 2>&1 &
APP_PID=$!
for i in $(seq 1 20); do curl -s http://127.0.0.1:5050/salud | grep -q stark-portal && break; sleep 1; done
cat "$EV/03_app_salida.txt"
echo "(PID de la app: $APP_PID)"

{
titulo "5. Verificación de servicios y endpoints"
cmd "lsof -nP -iTCP:5050 -sTCP:LISTEN"
cmd "curl -s http://127.0.0.1:5050/salud; echo"
cmd "curl -s -o /dev/null -w 'GET /login -> HTTP %{http_code}\n' http://127.0.0.1:5050/login"
for r in /dashboard /buscar /comentarios /perfil/2 /api/ordenes/2; do
  cmd "curl -s -o /dev/null -w 'GET $r (sin sesión) -> HTTP %{http_code} %{redirect_url}\n' http://127.0.0.1:5050$r"
done
rm -f /tmp/stark_cookies.txt
cmd "curl -s -c /tmp/stark_cookies.txt -o /dev/null -w 'POST /login (luis.oper) -> HTTP %{http_code} %{redirect_url}\n' -d 'username=luis.oper&password=Turno1!2026' http://127.0.0.1:5050/login"
for r in /dashboard "/buscar?q=buje" /comentarios /perfil/2; do
  cmd "curl -s -b /tmp/stark_cookies.txt -o /dev/null -w 'GET $r (con sesión) -> HTTP %{http_code}\n' 'http://127.0.0.1:5050$r'"
done
cmd "curl -s -b /tmp/stark_cookies.txt http://127.0.0.1:5050/api/ordenes/2; echo"
rm -f /tmp/stark_cookies.txt
} 2>&1 | tee "$EV/04_endpoints.txt"

titulo "6. Capturas del navegador"
if [ $ZAP_OK = 1 ]; then
  python tools/capturas.py --zap http://127.0.0.1:8090
else
  python tools/capturas.py
fi

if [ $ZAP_OK = 1 ]; then
  titulo "7. Análisis con OWASP ZAP"
  python tools/zap_scan.py 2>&1 | tee "$EV/05_zap.txt"
  python - <<'EOF'
from pathlib import Path
from playwright.sync_api import sync_playwright
ev = Path("evidencias")
rep = (ev / "zap-reporte-antes.html").resolve()
if rep.exists():
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, channel="chrome")
        pg = b.new_page(viewport={"width": 1280, "height": 900})
        pg.goto(rep.as_uri())
        pg.screenshot(path=str(ev / "capturas" / "a9_zap_reporte.png"))
        pg.screenshot(path=str(ev / "capturas" / "a9_zap_reporte_completo.png"), full_page=True)
        b.close()
    print("  captura -> evidencias/capturas/a9_zap_reporte.png")
EOF
  kill $ZAP_PID 2>/dev/null
fi

titulo "8. Registros generados"
tail -n 15 logs/app.log | tee "$EV/06_log_muestra.txt"

kill $APP_PID 2>/dev/null
titulo "LISTO"
echo "Evidencias en: $EV"
ls -1 "$EV" "$EV/capturas"
