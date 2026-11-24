"""
Configura OWASP ZAP (modo daemon, API local) y analiza la app de laboratorio.

Pasos: contexto limitado a la app, exclusión de /logout, sesión autenticada
(luis.oper) agregada a todas las peticiones, Spider, Active Scan y reporte HTML.

Uso: python tools/zap_scan.py   (ZAP debe estar escuchando en 127.0.0.1:8090)
"""
import json
import os
import sys
import time
from pathlib import Path

import requests

ZAP = "http://127.0.0.1:8090"
APP = "http://127.0.0.1:5050"
EVID = Path(__file__).resolve().parent.parent / "evidencias"
EVID.mkdir(exist_ok=True)
SUF = os.environ.get("ZAP_SUFIJO", "antes")
log_cfg = []


def api(path, **params):
    r = requests.get(f"{ZAP}/JSON/{path}/", params=params, timeout=60)
    r.raise_for_status()
    return r.json()


def paso(texto):
    print(f"[ZAP] {texto}")
    log_cfg.append(texto)


version = api("core/view/version")["version"]
paso(f"OWASP ZAP versión {version} en modo daemon, API en {ZAP}")

# 1. Contexto limitado a la aplicación de laboratorio
ctx = api("context/action/newContext", contextName="stark-lab")["contextId"]
api("context/action/includeInContext", contextName="stark-lab", regex=f"{APP}.*")
api("context/action/excludeFromContext", contextName="stark-lab", regex=".*/logout.*")
api("spider/action/excludeFromScan", regex=".*/logout.*")
api("ascan/action/excludeFromScan", regex=".*/logout.*")
paso(f"Contexto 'stark-lab' (id {ctx}): incluye {APP}.* ; excluye /logout")

# 2. Sesión autenticada: iniciar sesión como luis.oper y reutilizar la cookie
s = requests.Session()
s.post(f"{APP}/login", data={"username": "luis.oper", "password": "Turno1!2026"})
cookie = s.cookies.get("session")
if not cookie:
    sys.exit("No se pudo iniciar sesión en la app; ¿está corriendo?")
regla = dict(enabled="true", matchType="REQ_HEADER", matchRegex="false", matchString="Cookie",
             replacement=f"session={cookie}", initiators="")
try:  # ZAP guarda las reglas entre corridas: se borra la anterior para no duplicarla
    api("replacer/action/removeRule", description="sesion-luis.oper")
except requests.HTTPError:
    pass
try:
    api("replacer/action/addRule", description="sesion-luis.oper", **regla)
except requests.HTTPError:
    api("replacer/action/addRule", description=f"sesion-luis.oper-{int(time.time())}", **regla)
paso("Autenticación: sesión de luis.oper (stark_oper) agregada a todas las peticiones (regla Replacer)")

# 3. Spider
api("core/action/accessUrl", url=APP + "/", followRedirects="true")
sid = api("spider/action/scan", url=APP + "/", contextName="stark-lab", recurse="true")["scan"]
while int(api("spider/view/status", scanId=sid)["status"]) < 100:
    time.sleep(2)
urls = api("spider/view/results", scanId=sid)["results"]
paso(f"Spider terminado: {len(urls)} URLs descubiertas")

# 4. Esperar al análisis pasivo
while int(api("pscan/view/recordsToScan")["recordsToScan"]) > 0:
    time.sleep(1)
paso("Análisis pasivo terminado")

# 5. Active Scan (política por defecto, máximo 10 min)
api("ascan/action/setOptionMaxScanDurationInMins", Integer="10")
aid = api("ascan/action/scan", url=APP + "/", recurse="true", contextId=ctx)["scan"]
ultimo = -1
while True:
    pct = int(api("ascan/view/status", scanId=aid)["status"])
    if pct != ultimo and pct % 10 == 0:
        print(f"[ZAP] Active Scan {pct}%")
        ultimo = pct
    if pct >= 100:
        break
    time.sleep(3)
paso("Active Scan terminado (política por defecto)")

# 6. Alertas y reporte
alertas = api("core/view/alerts", baseurl=APP, start="0", count="5000")["alerts"]
resumen = {}
for a in alertas:
    clave = (a["risk"], a["alert"])
    resumen.setdefault(clave, set()).add(a["url"].split("?")[0])
orden = {"High": 0, "Medium": 1, "Low": 2, "Informational": 3}
lineas = []
for (riesgo, nombre), urls_a in sorted(resumen.items(), key=lambda kv: (orden.get(kv[0][0], 9), kv[0][1])):
    lineas.append(f"{riesgo:<13} {nombre}  ({len(urls_a)} URL)")
    for u in sorted(urls_a):
        lineas.append(f"{'':<13}   - {u}")
(EVID / f"zap_alertas_{SUF}.txt").write_text("\n".join(lineas) + "\n", encoding="utf-8")
(EVID / f"zap_alertas_{SUF}.json").write_text(json.dumps(alertas, indent=2, ensure_ascii=False), encoding="utf-8")

html = requests.get(f"{ZAP}/OTHER/core/other/htmlreport/", timeout=120).text
(EVID / f"zap-reporte-{SUF}.html").write_text(html, encoding="utf-8")
paso(f"{len(alertas)} alertas; reporte en evidencias/zap-reporte-{SUF}.html")

(EVID / f"zap_configuracion_{SUF}.txt").write_text("\n".join(log_cfg) + "\n", encoding="utf-8")
print("\n".join(lineas))
