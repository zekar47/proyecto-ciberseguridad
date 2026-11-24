# Stark Manufactura · Portal interno (Parte A)

Aplicación web de laboratorio en **Python + Flask + SQLite** para la Parte A del Proyecto Final de Ciberseguridad (Tecmilenio). Todos los datos son ficticios. Solo se ejecuta en `127.0.0.1`.

## Versiones en el repositorio

| Tag / rama | Contenido |
|------------|-----------|
| `v1-vulnerable` (commit inicial en `main`) | App intencionalmente vulnerable + evidencias de las Actividades 1 y 2 |
| `fix/vulnerabilidades` → PR → `v2-segura` | App corregida + evidencias de las Actividades 4 y 5 |

```bash
git checkout v1-vulnerable   # versión vulnerable
git checkout v2-segura       # versión corregida
git diff v1-vulnerable v2-segura -- parte-a-app-web/app.py parte-a-app-web/templates
```

## Vulnerabilidades y correcciones

| ID | Vulnerabilidad (v1) | Endpoint(s) | Corrección (v2) |
|----|---------------------|-------------|-----------------|
| 1 | SQL Injection | `POST /login`, `GET /buscar?q=` | Consultas parametrizadas (`?`), contraseñas con hash (`werkzeug.security`), mensajes de error genéricos |
| 2 | XSS reflejado y almacenado | `GET /buscar?q=`, `POST /comentarios` | Se quitó `|safe` (escapado automático de Jinja2), Content-Security-Policy estricta, CSS en archivo externo, longitud máxima de entradas |
| 3 | IDOR / BOLA | `GET /perfil/<id>`, `GET /api/ordenes/<id>` | Validación de autorización: solo el propietario o el perfil `stark_ti`; si no, `403` y evento `acceso_denegado` |

En `app.py` cada corrección está marcada con `FIX-1`, `FIX-2` o `FIX-3`.

## Ejecución

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python app.py                      # http://127.0.0.1:5050
```

Se usa el puerto 5050 porque en macOS el 5000 lo ocupa el Receptor AirPlay.

## Cuentas de prueba (ficticias, solo laboratorio)

| Usuario | Contraseña | Perfil |
|---------|-----------|--------|
| ana.ti | TI#Stark2026 | stark_ti (administración) |
| luis.oper | Turno1!2026 | stark_oper |
| sofia.consulta | Consulta*26 | stark_consulta |
| mgarza.rh | RH-Garza-26 | stark_consulta |

## Pruebas y evidencias

| Script | Qué hace |
|--------|----------|
| `exploits/demo_vulns.py` | Ejecuta las 7 pruebas de ataque e imprime `VULNERABLE` o `PROTEGIDO` |
| `evidencias.sh` | Actividad 1: entorno, ejecución, endpoints y capturas |
| `evidencias_zap.sh` | Actividad 1: instala ZAP multiplataforma y hace el escaneo autenticado |
| `evidencias_vulns.sh` | Actividad 2: demostración de las vulnerabilidades (v1) |
| `evidencias_fix.sh` | Actividades 4 y 5: repite las pruebas, ZAP "después", eventos controlados y análisis de registros |
| `tools/eventos_controlados.py` | Genera eventos de seguridad controlados (fuerza bruta, 403, 404, inyecciones) |
| `tools/analizar_logs.py` | Resume `logs/app.log` y emite alertas (fuerza bruta, enumeración, inyección) |

Las salidas y capturas están en `evidencias/` (`capturas/`, `capturas_vulns/` = antes, `capturas_fix/` = después).

## Registros de seguridad

`logs/app.log` registra cada petición (IP, usuario, método, ruta, estado) y eventos en formato `clave=valor`:
`login_exitoso`, `login_fallido`, `acceso_denegado`, `entrada_sospechosa`.

## Limitaciones conocidas

- No hay tokens anti-CSRF (ZAP lo reporta como riesgo medio); `SameSite=Lax` lo mitiga parcialmente.
- El servidor de desarrollo de Flask no es apto para producción.
- La detección de entradas sospechosas es por patrones y puede dar falsos positivos (por ejemplo, un apóstrofe en un nombre).
