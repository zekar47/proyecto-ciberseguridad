# Parte A · Actividades 1 y 2

Aplicación evaluada: **Stark Manufactura · Portal interno**, una app de laboratorio en Flask hecha intencionalmente vulnerable. Toda la información es ficticia y las pruebas se hicieron únicamente sobre esta aplicación, en un entorno local.

---

## Actividad 1. Preparación del entorno

### 1.1 Entorno local

| Elemento | Valor |
|----------|-------|
| Sistema operativo | _(anotar: Arch Linux / macOS / Windows)_ |
| Python | 3.10 o superior _(anotar versión: `python3 --version`)_ |
| Framework | Flask 3.x |
| Base de datos | SQLite (`stark.db`, se regenera al iniciar) |
| Herramienta de análisis | OWASP ZAP _(anotar versión)_ |
| Dirección de la app | `http://127.0.0.1:5050` (o `http://192.168.56.1:5050` en la red host-only) |

### 1.2 Ejecución de la aplicación

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

Salida esperada:

```
[!] App intencionalmente vulnerable escuchando en http://127.0.0.1:5050
```

📸 **Evidencia 1:** terminal con la app corriendo.

### 1.3 Verificación de servicios y endpoints

```bash
curl http://127.0.0.1:5050/salud
# {"estado":"ok","servicio":"stark-portal"}

curl -i http://127.0.0.1:5050/dashboard
# HTTP/1.1 302 FOUND  -> Location: /login  (las rutas internas piden sesión)
```

| Endpoint | Método | ¿Requiere sesión? | Resultado esperado |
|----------|--------|-------------------|--------------------|
| `/salud` | GET | No | `200` JSON `{"estado":"ok"}` |
| `/login` | GET/POST | No | Formulario / redirección al dashboard |
| `/dashboard` | GET | Sí | Órdenes del usuario |
| `/buscar?q=` | GET | Sí | Tabla de productos |
| `/comentarios` | GET/POST | Sí | Tablero de avisos |
| `/perfil/<id>` | GET | Sí | Datos del empleado |
| `/api/ordenes/<id>` | GET | Sí | JSON de la orden de trabajo |

📸 **Evidencia 2:** navegador con el login, el dashboard después de entrar como `luis.oper` y la respuesta de `/salud`.

### 1.4 Configuración de OWASP ZAP

1. Instalar ZAP: https://www.zaproxy.org/download/ (en Kali: `sudo apt install zaproxy`; en Arch, el paquete `zaproxy` del AUR).
2. Abrir ZAP y elegir **"No, I do not want to persist this session"**.
3. **Crear el contexto:** en *Sites*, clic derecho sobre `http://127.0.0.1:5050` → *Include in Context → New Context*. Así el escaneo queda limitado a la app de laboratorio.
4. **Exploración manual autenticada:** *Quick Start → Manual Explore*, URL `http://127.0.0.1:5050`, navegador Firefox o Chrome → *Launch Browser*. En ese navegador:
   - iniciar sesión como `luis.oper / Turno1!2026`,
   - visitar Catálogo (buscar "buje"), Avisos (publicar un aviso), Mi perfil y "Ver (API)".
   ZAP registra todas las peticiones con la cookie de sesión.
5. **Spider:** clic derecho sobre el sitio → *Attack → Spider*.
6. **Active Scan:** clic derecho sobre el sitio → *Attack → Active Scan* (política por defecto).
   - Para que el escaneo no cierre la sesión: *Context → Structure* o excluir `/logout` (clic derecho sobre `/logout` → *Exclude from → Scanner*).
7. Revisar la pestaña **Alerts** y exportar el reporte: *Report → Generate Report* (HTML) → guardar en `evidencias/zap-antes.html`.

> Si ZAP corre en la VM de Kali, arranca la app con `STARK_HOST=192.168.56.1 python app.py` y usa `http://192.168.56.1:5050` como objetivo.

📸 **Evidencia 3:** ZAP con el contexto creado, el árbol de *Sites* poblado y la pestaña *Alerts* después del escaneo.

**Nota:** ZAP suele detectar el XSS reflejado, la inyección SQL y los encabezados de seguridad faltantes, pero **no detecta el IDOR/BOLA** porque no sabe a qué usuario pertenece cada recurso. Ese caso se prueba manualmente (sección 2.3). Los resultados exactos de ZAP pueden variar con la versión y la política de escaneo, así que se reportan los que aparezcan.

---

## Actividad 2. Identificación de vulnerabilidades

Prueba automatizada que reproduce todos los casos (con la app corriendo):

```bash
python exploits/demo_vulns.py | tee evidencias/salida_demo_vulns.txt
```

📸 **Evidencia 4:** salida del script con las 7 pruebas en `[VULNERABLE]`.

---

### 2.1 SQL Injection (VULN-1)

| Campo | Detalle |
|-------|---------|
| **Componente / endpoint** | `POST /login` (campos `username`, `password`) y `GET /buscar?q=` → funciones `login()` y `buscar()` en `app.py` |
| **Descripción del problema** | La consulta SQL se arma concatenando directamente lo que escribe el usuario (f-string). Si la entrada lleva comillas o palabras reservadas de SQL, cambia la estructura de la consulta. Además, la app muestra los errores de SQLite en pantalla, lo que le facilita al atacante entender la consulta. |
| **Código vulnerable** | `f"SELECT ... FROM usuarios WHERE username = '{username}' AND password = '{password}'"` |

**Procedimiento de prueba**

*Caso A: evasión de autenticación en `/login`*
1. En el login escribir usuario: `ana.ti' --` y contraseña: `x` (cualquier valor).
2. La consulta queda así:
   `SELECT ... WHERE username = 'ana.ti' --' AND password = 'x'`
   Todo lo que va después de `--` es un comentario, así que nunca se valida la contraseña.

*Caso B: extracción de datos con `UNION` en `/buscar`*
1. Entrar con una cuenta de bajo privilegio (`sofia.consulta`).
2. Buscar: `zzz' UNION SELECT username, password, rol FROM usuarios --`
3. La consulta original no devuelve productos (`zzz`) y el `UNION` agrega las filas de la tabla `usuarios`.

*Caso C: error expuesto*: buscar solo `'` (una comilla).

**Resultado observado**
- Caso A: se entra al dashboard como **Ana Torres (stark_ti)** sin conocer su contraseña.
- Caso B: la tabla del catálogo muestra **los usuarios, sus contraseñas en texto plano y su perfil**.
- Caso C: la página muestra `Error de base de datos: unrecognized token ...`.
- En `logs/app.log` aparece la consulta alterada (`consulta_login=...ana.ti' --...`).

📸 **Evidencia 5:** login con el payload → dashboard de ana.ti. **Evidencia 6:** catálogo mostrando usuarios y contraseñas.

**Riesgo e impacto potencial: Crítico**
- Suplantación de cualquier cuenta, incluida la de administración de TI (`stark_ti`).
- Robo de credenciales de todos los empleados, que pueden reutilizarse en otros sistemas de Stark (correo, ERP, VPN). Es el mismo vector de acceso inicial del escenario de ransomware del avance, pero sin necesidad de phishing.
- Lectura de cualquier tabla: datos de nómina, órdenes de trabajo e información comercial (posible incumplimiento de la LFPDPPP).
- Según el motor y los permisos, también se podrían modificar o borrar datos.

---

### 2.2 Cross-Site Scripting, XSS (VULN-2)

| Campo | Detalle |
|-------|---------|
| **Componente / endpoint** | **Reflejado:** `GET /buscar?q=` → `templates/buscar.html`. **Almacenado:** `POST /comentarios` → `templates/comentarios.html` |
| **Descripción del problema** | Jinja2 escapa el HTML por defecto, pero las plantillas usan el filtro `|safe` (`{{ q|safe }}`, `{{ c.texto|safe }}`), que desactiva ese escapado. El contenido que manda el usuario se inserta en la página como HTML/JavaScript real. En el caso almacenado, el script queda guardado en la base de datos y se ejecuta para **cualquier** empleado que abra el tablero. La cookie de sesión tampoco tiene restricciones adicionales y no hay Content-Security-Policy. |

**Procedimiento de prueba**

*Caso A: reflejado*
1. Con sesión iniciada, abrir:
   `http://127.0.0.1:5050/buscar?q=<script>alert('XSS-Stark')</script>`
2. Un atacante podría mandar esta URL por correo a un empleado (como en el phishing del avance).

*Caso B: almacenado*
1. Como `sofia.consulta`, publicar en **Avisos**:
   `<img src=x onerror="alert('XSS almacenado: '+document.cookie)">`
2. Cerrar sesión, entrar como `luis.oper` y abrir **Avisos**.

**Resultado observado**
- Caso A: el navegador muestra la alerta `XSS-Stark`; en el código fuente de la página el `<script>` aparece sin escapar.
- Caso B: al abrir la página como `luis.oper` se ejecuta el script. La cookie de sesión de Flask tiene `HttpOnly`, así que `document.cookie` sale vacío; aun así, el script puede hacer peticiones **con la sesión de la víctima** (por ejemplo `fetch('/api/ordenes/2')`) y leer sus datos. Se ejecuta cada vez que alguien abre los avisos.

📸 **Evidencia 7:** alerta del XSS reflejado. **Evidencia 8:** alerta del XSS almacenado abierta por otro usuario. **Evidencia 9:** alerta correspondiente en ZAP (si aparece).

**Riesgo e impacto potencial: Alto**
- Acciones y lectura de datos con la sesión de quien abra la página, incluidos los administradores de TI. Si la cookie no tuviera `HttpOnly`, también se podría robar la sesión.
- Acciones en nombre de la víctima (publicar, consultar datos) sin que se dé cuenta.
- Mostrar formularios falsos dentro del portal legítimo para robar contraseñas (phishing interno muy creíble).
- Redirigir a sitios que descarguen malware, otro posible punto de entrada para el ransomware.

---

### 2.3 Control de acceso roto, IDOR / BOLA (VULN-3)

| Campo | Detalle |
|-------|---------|
| **Componente / endpoint** | `GET /perfil/<id>` (IDOR) y `GET /api/ordenes/<id>` (BOLA) → funciones `perfil()` y `api_reporte()` en `app.py` |
| **Descripción del problema** | Las rutas solo verifican que exista **una** sesión (`@login_requerido`), pero no que el recurso pedido le pertenezca al usuario o que su perfil tenga permiso. Los IDs son números consecutivos fáciles de adivinar, así que basta con cambiar el número en la URL. |
| **Código vulnerable** | `SELECT ... FROM reportes WHERE id = ?` sin la condición `AND usuario_id = <usuario en sesión>` |

**Procedimiento de prueba**
1. Iniciar sesión como `luis.oper` (operador CNC, id 2).
2. En el dashboard solo aparece **su** orden: `OT-1002`. Abrir "Ver (API)" → `/api/ordenes/2` (acceso legítimo).
3. Cambiar la URL a `/api/ordenes/4` y luego a `/api/ordenes/1`.
4. Ir a "Mi perfil" (`/perfil/2`) y cambiar la URL a `/perfil/4` y `/perfil/1`.
5. (Opcional, con ZAP) Enviar la petición a *Fuzzer* o *Requester* y recorrer los IDs del 1 al 10.

**Resultado observado**
- `/api/ordenes/4` devuelve `200 OK` con la orden **"OT-1004 Nómina noviembre"**, clasificada como *Confidencial* y perteneciente a Recursos Humanos.
- `/api/ordenes/1` devuelve el inventario de servidores de TI (direcciones y funciones de SRV-STARK-01).
- `/perfil/4` muestra nombre, correo y teléfono de María Garza (RH).
- En el log, `usuario=luis.oper ruta=/api/ordenes/4 estado=200`: el acceso indebido quedó registrado como exitoso.

📸 **Evidencia 10:** dashboard de luis.oper (solo OT-1002). **Evidencia 11:** `/api/ordenes/4` respondiendo con la orden de nómina. **Evidencia 12:** `/perfil/4`.

**Riesgo e impacto potencial: Alto**
- Cualquier empleado, incluido un operador de piso o una cuenta robada por phishing, puede leer información confidencial de otras áreas: nómina, inventario de infraestructura, información comercial.
- Exposición de datos personales de empleados (posible incumplimiento de la LFPDPPP y obligación de notificar).
- El inventario de servidores le ayuda a un atacante a planear movimiento lateral y a elegir qué cifrar, igual que en el escenario de ransomware.
- Rompe el principio de mínimo privilegio definido en los perfiles del avance (`stark_ti`, `stark_oper`, `stark_consulta`).

---

### Resumen de hallazgos

| # | Vulnerabilidad | Endpoint | Severidad | Detectada por ZAP | Confirmada manualmente |
|---|----------------|----------|-----------|-------------------|------------------------|
| 1 | SQL Injection | `/login`, `/buscar` | Crítica | _(anotar)_ | Sí |
| 2 | XSS reflejado / almacenado | `/buscar`, `/comentarios` | Alta | _(anotar)_ | Sí |
| 3 | IDOR / BOLA | `/perfil/<id>`, `/api/ordenes/<id>` | Alta | No (requiere lógica de negocio) | Sí |

**Para la Actividad 3 (correcciones):** consultas parametrizadas en `login()` y `buscar()` y no mostrar el error de SQL; quitar `|safe` en las dos plantillas (y opcionalmente agregar CSP y `HttpOnly` en la cookie); validar en `perfil()` y `api_reporte()` que el recurso pertenezca al usuario en sesión o que su perfil sea `stark_ti`, y si no, responder `403`. Después, volver a correr `exploits/demo_vulns.py`: todo debe salir `[PROTEGIDO]`.
