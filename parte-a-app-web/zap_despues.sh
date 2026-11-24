#!/usr/bin/env bash
# Repite solo el escaneo de OWASP ZAP con la versión corregida y verifica las cabeceras de seguridad.
# Uso:  cd ~/Desktop/vulnerable && bash zap_despues.sh
set -u
cd "$(dirname "$0")"
EV="$(pwd)/evidencias"; mkdir -p "$EV/capturas_fix"
source .venv/bin/activate
titulo() { printf '\n==================== %s ====================\n' "$1"; }
cmd() { printf '\n$ %s\n' "$*"; eval "$@"; }

python app.py > /dev/null 2>&1 &
APP_PID=$!
for i in $(seq 1 20); do curl -s http://127.0.0.1:5050/salud | grep -q stark-portal && break; sleep 1; done

{
titulo "A4. Cabeceras de seguridad (versión corregida)"
J=/tmp/stark_j.txt; rm -f $J
cmd "curl -s -c $J -o /dev/null -d 'username=sofia.consulta&password=Consulta*26' http://127.0.0.1:5050/login"
cmd "curl -s -b $J -D - -o /dev/null http://127.0.0.1:5050/buscar | grep -iE 'content-security|x-content-type|x-frame|referrer'"
rm -f $J
} 2>&1 | tee "$EV/14b_cabeceras_fix.txt"

ZAPSH="$(ls -d .tools/ZAP_*/zap.sh 2>/dev/null | tail -1)"
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
JAVA="$(command -v java 2>/dev/null)"; "$JAVA" -version >/dev/null 2>&1 || JAVA="$("$BREW" --prefix openjdk)/bin/java"
export PATH="$(dirname "$JAVA"):$PATH"
titulo "A4. OWASP ZAP después de las correcciones"
bash "$ZAPSH" -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true \
     -config start.checkForUpdates=false > "$EV/zap_daemon_despues.log" 2>&1 &
ZAP_PID=$!
for i in $(seq 1 120); do curl -s http://127.0.0.1:8090/JSON/core/view/version/ >/dev/null 2>&1 && break; sleep 2; done
python tools/capturas.py --zap http://127.0.0.1:8090 > /dev/null
ZAP_SUFIJO=despues python tools/zap_scan.py 2>&1 | tee "$EV/16_zap_despues.txt"
python - <<'PY'
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
PY
kill $ZAP_PID $APP_PID 2>/dev/null
titulo "LISTO"
