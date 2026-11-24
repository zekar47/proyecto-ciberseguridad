# Stark Manufactura · Portal interno (app vulnerable de laboratorio)

Aplicación web en **Python + Flask + SQLite** hecha **a propósito con vulnerabilidades** para la Parte A del Proyecto Final de Ciberseguridad (Tecmilenio).

> ⚠️ Sólo para laboratorio local. No la despliegues en internet ni en una red compartida. Todos los datos (empleados, correos, órdenes, contraseñas) son ficticios.

## Vulnerabilidades incluidas

| ID | Vulnerabilidad | Endpoint(s) | Dónde está en el código |
|----|----------------|-------------|-------------------------|
| VULN-1 | SQL Injection | `POST /login`, `GET /buscar?q=` | `app.py` → `login()`, `buscar()` |
| VULN-2 | XSS reflejado y almacenado | `GET /buscar?q=`, `POST /comentarios` | `templates/buscar.html`, `templates/comentarios.html` (filtro `|safe`) |
| VULN-3 | IDOR / BOLA | `GET /perfil/<id>`, `GET /api/ordenes/<id>` | `app.py` → `perfil()`, `api_reporte()` |

Busca `VULN-` en el código para encontrar cada punto.

## Requisitos

- Python 3.10 o superior
- (Opcional) OWASP ZAP para el análisis automatizado

## Ejecución

```bash
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

Abre http://127.0.0.1:5050. (Se usa el puerto 5050 porque en macOS el 5000 lo ocupa el Receptor AirPlay.) La base de datos `stark.db` se **reinicia en cada arranque**.

Para analizarla desde la VM de Kali por la red host-only del avance:

```bash
STARK_HOST=192.168.56.1 python app.py
```

## Cuentas de prueba (ficticias)

| Usuario | Contraseña | Perfil |
|---------|-----------|--------|
| ana.ti | TI#Stark2026 | stark_ti |
| luis.oper | Turno1!2026 | stark_oper |
| sofia.consulta | Consulta*26 | stark_consulta |
| mgarza.rh | RH-Garza-26 | stark_consulta |

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/salud` | Estado del servicio (sin sesión) |
| GET/POST | `/login` | Inicio de sesión |
| GET | `/dashboard` | Órdenes de trabajo del usuario |
| GET | `/buscar?q=` | Catálogo de productos |
| GET/POST | `/comentarios` | Tablero de avisos |
| GET | `/perfil/<id>` | Perfil de empleado |
| GET | `/api/ordenes/<id>` | API JSON de órdenes de trabajo |
| GET | `/logout` | Cerrar sesión |

## Demostración automática de las vulnerabilidades

Con la app corriendo, en otra terminal:

```bash
python exploits/demo_vulns.py
```

Cada prueba imprime `[VULNERABLE]` o `[PROTEGIDO]`. Después de aplicar las correcciones, todas deben salir `[PROTEGIDO]` (sirve como evidencia para la Actividad 4).

## Registros

Cada petición queda en `logs/app.log` (IP, usuario, método, ruta, estado), al igual que los intentos de inicio de sesión fallidos y los errores de SQL. Sirve como base para la Actividad 5.

## Documentación

- [`docs/actividad-1-2.md`](docs/actividad-1-2.md): preparación del entorno, configuración de OWASP ZAP e identificación de las vulnerabilidades.
- `evidencias/`: salidas y capturas de pantalla.
