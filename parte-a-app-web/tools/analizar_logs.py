"""
Actividad 5: analiza logs/app.log y resume los eventos de seguridad.

Detecta:
  - Fuerza bruta: 5 o más login_fallido desde la misma IP en 60 segundos
  - Enumeración de recursos (IDOR/BOLA): 3 o más acceso_denegado del mismo usuario
  - Intentos de inyección: entradas con patrones de SQLi o XSS
  - Solicitudes inválidas: respuestas 400 y 404

Uso: python tools/analizar_logs.py [ruta_del_log]
"""
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

LOG = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "logs" / "app.log"
linea_re = re.compile(r"^(\S+ \S+),\d+ (\w+) (.*)$")
kv_re = re.compile(r"(\w+)=('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"|\S+)")

eventos, peticiones = [], []
for linea in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
    m = linea_re.match(linea)
    if not m:
        continue
    ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
    campos = {k: (v[1:-1] if len(v) > 1 and v[0] in "'\"" and v[-1] == v[0] else v)
              for k, v in kv_re.findall(m.group(3))}
    if "evento" in campos:
        eventos.append((ts, m.group(2), campos))
    elif "estado" in campos:
        peticiones.append((ts, campos))

print(f"Archivo analizado: {LOG.name}  ({len(peticiones)} peticiones, {len(eventos)} eventos de seguridad)\n")

print("Eventos por tipo")
for tipo, n in Counter(e[2]["evento"] for e in eventos).most_common():
    print(f"  {tipo:<20} {n:>3}")

estados = Counter(p[1]["estado"] for p in peticiones)
print("\nRespuestas HTTP por código")
for cod in sorted(estados):
    print(f"  {cod:<20} {estados[cod]:>3}")

alertas = []
fallidos = defaultdict(list)
for ts, _, c in eventos:
    if c["evento"] == "login_fallido":
        fallidos[c["ip"]].append((ts, c.get("usuario_ingresado", "?")))
for ip, lista in fallidos.items():
    for i in range(len(lista)):
        ventana = [x for x in lista[i:] if x[0] - lista[i][0] <= timedelta(seconds=60)]
        if len(ventana) >= 5:
            cuentas = sorted({u for _, u in ventana})
            alertas.append(("ALTA", f"Posible fuerza bruta: {len(ventana)} logins fallidos en 60 s desde {ip} "
                                    f"(cuentas: {', '.join(cuentas)})"))
            break

denegados = defaultdict(list)
for ts, _, c in eventos:
    if c["evento"] == "acceso_denegado":
        denegados[c["usuario"]].append(f"{c.get('recurso')}/{c.get('id')}")
for usuario, recursos in denegados.items():
    if len(recursos) >= 3:
        alertas.append(("ALTA", f"Posible enumeración de recursos (IDOR/BOLA): {usuario} tuvo {len(recursos)} "
                                f"accesos denegados ({', '.join(recursos)})"))

sosp = [c for _, _, c in eventos if c["evento"] == "entrada_sospechosa"]
if sosp:
    por_usuario = Counter(c["usuario"] for c in sosp)
    alertas.append(("MEDIA", f"Intentos de inyección (SQLi/XSS): {len(sosp)} entradas sospechosas "
                             f"({', '.join(f'{u}: {n}' for u, n in por_usuario.items())})"))
invalidas = [p for p in peticiones if p[1]["estado"] in ("400", "404")]
if invalidas:
    rutas = Counter(p[1]["ruta"] for p in invalidas)
    alertas.append(("BAJA", f"Solicitudes inválidas: {len(invalidas)} ({', '.join(rutas)})"))

print("\nAlertas")
for nivel, texto in alertas or [("-", "Sin alertas")]:
    print(f"  [{nivel}] {texto}")

print("\nDetalle de entradas sospechosas")
for c in sosp:
    print(f"  {c['usuario']:<15} {c.get('ruta', ''):<13} {c.get('campo', ''):<9} {c.get('valor', '')[:70]}")
