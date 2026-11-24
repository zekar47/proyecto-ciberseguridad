"""
Actividad 5: genera eventos de seguridad CONTROLADOS contra la app de laboratorio.

  1. Fuerza bruta simulada: 6 intentos de login fallidos seguidos para ana.ti
  2. Solicitudes inválidas: rutas e identificadores que no existen, aviso demasiado largo
  3. Accesos no autorizados: luis.oper intenta abrir órdenes y perfiles ajenos
  4. Entradas sospechosas: cargas típicas de SQL Injection y XSS
  5. Actividad legítima de referencia

Uso (con la app corriendo):  python tools/eventos_controlados.py
"""
import requests

BASE = "http://127.0.0.1:5050"


def login(s, u, p):
    return s.post(f"{BASE}/login", data={"username": u, "password": p}, allow_redirects=False)


def ver(desc, r):
    print(f"  {desc:<62} -> HTTP {r.status_code}")


print("1) Fuerza bruta simulada contra ana.ti")
s = requests.Session()
for clave in ["123456", "password", "admin", "Stark2026", "ana.ti", "qwerty"]:
    ver(f"POST /login ana.ti / {clave}", login(s, "ana.ti", clave))

print("2) Solicitudes inválidas")
a = requests.Session(); login(a, "sofia.consulta", "Consulta*26")
for ruta in ["/admin", "/api/ordenes/999", "/perfil/abc", "/backup.zip"]:
    ver(f"GET {ruta}", a.get(BASE + ruta))
ver("POST /comentarios (aviso de 600 caracteres)", a.post(f"{BASE}/comentarios", data={"texto": "A" * 600}))

print("3) Accesos no autorizados (luis.oper, perfil stark_oper)")
l = requests.Session(); login(l, "luis.oper", "Turno1!2026")
for ruta in ["/api/ordenes/1", "/api/ordenes/3", "/api/ordenes/4", "/perfil/1", "/perfil/4"]:
    ver(f"GET {ruta}", l.get(BASE + ruta))

print("4) Entradas sospechosas (SQLi / XSS)")
ver("POST /login usuario=ana.ti' --", login(requests.Session(), "ana.ti' --", "x"))
ver("GET /buscar?q=' UNION SELECT username,password,rol FROM usuarios --",
    a.get(f"{BASE}/buscar", params={"q": "' UNION SELECT username,password,rol FROM usuarios --"}))
ver("GET /buscar?q=<script>alert(1)</script>", a.get(f"{BASE}/buscar", params={"q": "<script>alert(1)</script>"}))
ver("POST /comentarios <img src=x onerror=alert(1)>",
    a.post(f"{BASE}/comentarios", data={"texto": "<img src=x onerror=alert(1)>"}, allow_redirects=False))

print("5) Actividad legítima de referencia")
t = requests.Session()
ver("POST /login ana.ti (contraseña correcta)", login(t, "ana.ti", "TI#Stark2026"))
ver("GET /api/ordenes/4 como ana.ti (stark_ti, autorizado)", t.get(f"{BASE}/api/ordenes/4"))
ver("GET /api/ordenes/2 como luis.oper (su propia orden)", l.get(f"{BASE}/api/ordenes/2"))
print("Eventos generados.")
