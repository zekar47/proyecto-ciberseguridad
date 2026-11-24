#!/usr/bin/env bash
# Instala (si hace falta) y ejecuta OWASP ZAP multiplataforma contra la app de laboratorio.
# Uso:  cd ~/vulnerable && bash evidencias_zap.sh
set -u
cd "$(dirname "$0")"
EV="$(pwd)/evidencias"; mkdir -p "$EV/capturas" .tools
source .venv/bin/activate

titulo() { printf '\n==================== %s ====================\n' "$1"; }

{
titulo "3. OWASP ZAP (versión multiplataforma)"
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"

# --- Java 17 o superior ---
JAVA=""
for j in "$(command -v java 2>/dev/null)" "$("$BREW" --prefix openjdk 2>/dev/null)/bin/java"; do
  if [ -n "$j" ] && [ -x "$j" ] && "$j" -version >/dev/null 2>&1; then
    v=$("$j" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
    [ "${v:-0}" -ge 17 ] 2>/dev/null && JAVA="$j" && break
  fi
done
if [ -z "$JAVA" ]; then
  echo '$ brew install openjdk'
  "$BREW" install openjdk
  JAVA="$("$BREW" --prefix openjdk)/bin/java"
fi
echo '$ java -version'; "$JAVA" -version 2>&1
export PATH="$(dirname "$JAVA"):$PATH"
export JAVA_HOME="$(cd "$(dirname "$JAVA")/.." && pwd)"

# --- ZAP multiplataforma desde el GitHub oficial ---
ZAPSH="$(ls -d .tools/ZAP_*/zap.sh 2>/dev/null | tail -1)"
if [ -z "$ZAPSH" ]; then
  URL=$(curl -s https://api.github.com/repos/zaproxy/zaproxy/releases/latest | python -c \
    "import sys,json; print(next(a['browser_download_url'] for a in json.load(sys.stdin)['assets'] if a['name'].endswith('_Crossplatform.zip')))")
  echo "\$ curl -L -o .tools/zap.zip $URL"
  curl -L --progress-bar -o .tools/zap.zip "$URL" && (cd .tools && unzip -q zap.zip && rm -f zap.zip)
  ZAPSH="$(ls -d .tools/ZAP_*/zap.sh 2>/dev/null | tail -1)"
fi
echo "ZAP: $ZAPSH"
} 2>&1 | tee "$EV/05a_zap_instalacion.txt"

ZAPSH="$(ls -d .tools/ZAP_*/zap.sh 2>/dev/null | tail -1)"
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
JAVA="$(command -v java 2>/dev/null)"; "$JAVA" -version >/dev/null 2>&1 || JAVA="$("$BREW" --prefix openjdk)/bin/java"
export PATH="$(dirname "$JAVA"):$PATH"
[ -z "$ZAPSH" ] && { echo "No se pudo instalar ZAP."; exit 1; }

titulo "Iniciando ZAP en modo daemon (127.0.0.1:8090)"
echo "\$ $ZAPSH -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true"
bash "$ZAPSH" -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true \
     -config start.checkForUpdates=false > "$EV/zap_daemon.log" 2>&1 &
ZAP_PID=$!
ZAP_OK=0
for i in $(seq 1 120); do
  curl -s http://127.0.0.1:8090/JSON/core/view/version/ >/dev/null 2>&1 && { ZAP_OK=1; break; }
  sleep 2
done
[ $ZAP_OK = 1 ] || { echo "ZAP no respondió; revisa evidencias/zap_daemon.log"; tail -20 "$EV/zap_daemon.log"; exit 1; }
echo "ZAP listo: $(curl -s http://127.0.0.1:8090/JSON/core/view/version/)"

titulo "Iniciando la aplicación"
python app.py > /dev/null 2>&1 &
APP_PID=$!
for i in $(seq 1 20); do curl -s http://127.0.0.1:5050/salud | grep -q stark-portal && break; sleep 1; done
curl -s http://127.0.0.1:5050/salud; echo

titulo "Exploración a través del proxy de ZAP"
python tools/capturas.py --zap http://127.0.0.1:8090

titulo "Spider + Active Scan"
python tools/zap_scan.py 2>&1 | tee "$EV/05b_zap_escaneo.txt"

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

kill $APP_PID $ZAP_PID 2>/dev/null
titulo "LISTO"
ls -1 "$EV" "$EV/capturas"
