"""
Stark Manufactura — Portal Interno (versión CORREGIDA).

Aplicación de laboratorio del Proyecto Final de Ciberseguridad (Tecmilenio).
La versión v1-vulnerable tenía tres vulnerabilidades; aquí están corregidas:

  [FIX-1] SQL Injection ........ consultas parametrizadas + contraseñas con hash
  [FIX-2] Cross-Site Scripting . escapado automático de Jinja2 (sin |safe) + CSP
  [FIX-3] IDOR / BOLA .......... validación de autorización sobre cada recurso

Además registra eventos de seguridad (login fallido, acceso denegado, entrada
sospechosa) en logs/app.log para apoyar la detección de incidentes.
Cada corrección está marcada en el código con "# FIX-x". Datos ficticios.
"""
import logging
import os
import re
import sqlite3
from functools import wraps
from pathlib import Path

from flask import (Flask, abort, g, jsonify, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "stark.db"
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)

app = Flask(__name__)
app.secret_key = os.environ.get("STARK_SECRET", "clave-de-laboratorio-no-usar-en-produccion")
# FIX-2: la cookie de sesión no es accesible desde JavaScript y no se envía en peticiones de otros sitios
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")

MAX_BUSQUEDA = 100
MAX_AVISO = 500
ROL_ADMIN = "stark_ti"

# ---------------------------------------------------------------------------
# Registro de eventos
# ---------------------------------------------------------------------------
logging.basicConfig(
    filename=LOG_DIR / "app.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("stark")
logging.getLogger("werkzeug").setLevel(logging.WARNING)  # evita líneas duplicadas del servidor


def evento(nivel, nombre, **detalle):
    """Escribe un evento de seguridad en formato clave=valor, fácil de filtrar."""
    extra = " ".join(f"{k}={str(v)!r}" for k, v in detalle.items())
    log.log(nivel, "evento=%s ip=%s usuario=%s %s", nombre, request.remote_addr,
            session.get("username", "-"), extra)


PATRONES_SOSPECHOSOS = re.compile(
    r"('|--|;|/\*|\bunion\b|\bselect\b|\bor\b\s+\S+\s*=|<\s*script|onerror\s*=|onload\s*=|javascript:)",
    re.IGNORECASE,
)


def revisar_entrada(campo, valor):
    """Solo DETECTA y registra patrones típicos de SQLi/XSS; la protección real son FIX-1 y FIX-2."""
    if valor and PATRONES_SOSPECHOSOS.search(valor):
        evento(logging.WARNING, "entrada_sospechosa", ruta=request.path, campo=campo, valor=valor[:120])


@app.after_request
def cabeceras_y_registro(resp):
    # FIX-2: cabeceras de seguridad. La CSP solo permite scripts y estilos del propio sitio,
    # así que un <script> inyectado no se ejecutaría aunque llegara al HTML.
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; "
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
    )
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "same-origin"
    if not request.path.startswith("/static/"):
        log.info("ip=%s usuario=%s metodo=%s ruta=%s estado=%s", request.remote_addr,
                 session.get("username", "-"), request.method,
                 request.full_path.rstrip("?"), resp.status_code)
    return resp


# ---------------------------------------------------------------------------
# Base de datos
# ---------------------------------------------------------------------------
def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def cerrar_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


USUARIOS = [
    # id, usuario, contraseña (solo para crear el hash), nombre, puesto, correo, teléfono, perfil
    (1, "ana.ti", "TI#Stark2026", "Ana Torres", "Administradora de TI", "ana.torres@stark.example", "81-0000-0001", "stark_ti"),
    (2, "luis.oper", "Turno1!2026", "Luis Méndez", "Operador CNC", "luis.mendez@stark.example", "81-0000-0002", "stark_oper"),
    (3, "sofia.consulta", "Consulta*26", "Sofía Ramos", "Analista de compras", "sofia.ramos@stark.example", "81-0000-0003", "stark_consulta"),
    (4, "mgarza.rh", "RH-Garza-26", "María Garza", "Recursos Humanos", "maria.garza@stark.example", "81-0000-0004", "stark_consulta"),
]


def init_db():
    """Crea la base de datos con datos ficticios (se reinicia en cada arranque)."""
    if DB_PATH.exists():
        DB_PATH.unlink()
    con = sqlite3.connect(DB_PATH)
    con.executescript(
        """
        CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,          -- FIX-1: ya no se guarda en texto plano
            nombre TEXT NOT NULL, puesto TEXT NOT NULL, correo TEXT NOT NULL,
            telefono TEXT NOT NULL, rol TEXT NOT NULL
        );
        CREATE TABLE productos (id INTEGER PRIMARY KEY, nombre TEXT NOT NULL, categoria TEXT NOT NULL, precio REAL NOT NULL);
        CREATE TABLE reportes (
            id INTEGER PRIMARY KEY, usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
            titulo TEXT NOT NULL, contenido TEXT NOT NULL, clasificacion TEXT NOT NULL
        );
        CREATE TABLE comentarios (id INTEGER PRIMARY KEY, autor TEXT NOT NULL, texto TEXT NOT NULL,
                                  fecha TEXT DEFAULT CURRENT_TIMESTAMP);

        INSERT INTO productos (nombre, categoria, precio) VALUES
          ('Soporte de suspensión SP-220','Autopartes',185.50),
          ('Brida troquelada BT-40','Autopartes',42.00),
          ('Bisagra de acero BL-12','Línea blanca',18.75),
          ('Eje maquinado EM-08','Autopartes',310.00),
          ('Panel lateral PL-60','Línea blanca',96.40),
          ('Buje de precisión BP-15','Autopartes',27.90);

        INSERT INTO reportes (usuario_id, titulo, contenido, clasificacion) VALUES
          (1,'OT-1001 Inventario de servidores','SRV-STARK-01 (192.168.56.1): archivos de ingeniería, identidad y respaldos.','Confidencial'),
          (2,'OT-1002 Programa CNC turno 1','Lote de 5,000 bujes BP-15, máquina CNC-03, entrega JIT viernes.','Interno'),
          (3,'OT-1003 Cotización de acero','Proveedor Aceros del Norte: 18.40 MXN/kg, contrato anual pendiente.','Interno'),
          (4,'OT-1004 Nómina noviembre','Total de nómina: 3.1 M MXN. RFC y NSS de empleados en expediente RH (datos ficticios).','Confidencial');

        INSERT INTO comentarios (autor, texto) VALUES
          ('mgarza.rh','Recuerden entregar sus incidencias de nómina antes del día 25.'),
          ('ana.ti','Mañana hay mantenimiento de SRV-STARK-01 a las 8 pm.');
        """
    )
    con.executemany(
        "INSERT INTO usuarios VALUES (?,?,?,?,?,?,?,?)",
        [(i, u, generate_password_hash(p), n, pu, c, t, r) for i, u, p, n, pu, c, t, r in USUARIOS],
    )
    con.commit()
    con.close()


# ---------------------------------------------------------------------------
# Autenticación y autorización
# ---------------------------------------------------------------------------
def login_requerido(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


def autorizado(propietario_id):
    """FIX-3: el recurso es del usuario en sesión, o el usuario es administrador de TI."""
    return session.get("user_id") == propietario_id or session.get("rol") == ROL_ADMIN


def negar(recurso, recurso_id, propietario_id):
    evento(logging.WARNING, "acceso_denegado", recurso=recurso, id=recurso_id, propietario=propietario_id)
    abort(403)


# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return redirect(url_for("dashboard" if "user_id" in session else "login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        revisar_entrada("username", username)

        # FIX-1: consulta parametrizada. El valor viaja aparte del texto SQL, así que
        # una comilla o "--" se tratan como parte del nombre de usuario, no como código.
        user = get_db().execute(
            "SELECT id, username, password_hash, nombre, rol FROM usuarios WHERE username = ?",
            (username,),
        ).fetchone()

        if user and check_password_hash(user["password_hash"], password):
            session.clear()
            session.update(user_id=user["id"], username=user["username"],
                           nombre=user["nombre"], rol=user["rol"])
            evento(logging.INFO, "login_exitoso")
            return redirect(url_for("dashboard"))
        evento(logging.WARNING, "login_fallido", usuario_ingresado=username[:60])
        error = "Usuario o contraseña incorrectos."   # mensaje genérico, sin detalles internos
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_requerido
def dashboard():
    reportes = get_db().execute(
        "SELECT id, titulo, clasificacion FROM reportes WHERE usuario_id = ?",
        (session["user_id"],),
    ).fetchall()
    return render_template("dashboard.html", reportes=reportes)


@app.route("/buscar")
@login_requerido
def buscar():
    q = request.args.get("q", "")[:MAX_BUSQUEDA]
    resultados = []
    if q:
        revisar_entrada("q", q)
        # FIX-1: parámetro en lugar de concatenación; el comodín % se agrega al valor, no al SQL.
        resultados = get_db().execute(
            "SELECT nombre, categoria, precio FROM productos WHERE nombre LIKE ?",
            (f"%{q}%",),
        ).fetchall()
    # FIX-2: la plantilla ya no usa |safe; Jinja2 escapa q automáticamente.
    return render_template("buscar.html", q=q, resultados=resultados)


@app.route("/comentarios", methods=["GET", "POST"])
@login_requerido
def comentarios():
    db = get_db()
    error = None
    if request.method == "POST":
        texto = request.form.get("texto", "").strip()
        if not texto or len(texto) > MAX_AVISO:
            error = f"El aviso debe tener entre 1 y {MAX_AVISO} caracteres."
        else:
            revisar_entrada("texto", texto)
            db.execute("INSERT INTO comentarios (autor, texto) VALUES (?, ?)", (session["username"], texto))
            db.commit()
            return redirect(url_for("comentarios"))
    filas = db.execute("SELECT autor, texto, fecha FROM comentarios ORDER BY id DESC").fetchall()
    # FIX-2: el texto se muestra escapado (sin |safe); un <script> guardado aparece como texto.
    return render_template("comentarios.html", comentarios=filas, error=error), (400 if error else 200)


@app.route("/perfil/<int:user_id>")
@login_requerido
def perfil(user_id):
    # FIX-3: solo el propio usuario o un administrador de TI pueden ver el perfil.
    if not autorizado(user_id):
        negar("perfil", user_id, user_id)
    u = get_db().execute(
        "SELECT id, username, nombre, puesto, correo, telefono, rol FROM usuarios WHERE id = ?",
        (user_id,),
    ).fetchone()
    if not u:
        abort(404)
    return render_template("perfil.html", u=u)


@app.route("/api/ordenes/<int:reporte_id>")
@login_requerido
def api_reporte(reporte_id):
    r = get_db().execute(
        "SELECT id, usuario_id, titulo, contenido, clasificacion FROM reportes WHERE id = ?",
        (reporte_id,),
    ).fetchone()
    # FIX-3: se responde 404 si no existe y 403 si existe pero no es del usuario.
    if not r:
        return jsonify({"error": "no encontrado"}), 404
    if not autorizado(r["usuario_id"]):
        negar("orden", reporte_id, r["usuario_id"])
    return jsonify(dict(r))


@app.errorhandler(403)
def prohibido(_e):
    if request.path.startswith("/api/"):
        return jsonify({"error": "acceso denegado"}), 403
    return render_template("mensaje.html", titulo="Acceso denegado",
                           texto="No tienes permiso para ver este recurso."), 403


@app.errorhandler(404)
def no_encontrado(_e):
    return render_template("mensaje.html", titulo="No encontrado", texto="El recurso no existe."), 404


@app.route("/salud")
def salud():
    return jsonify({"estado": "ok", "servicio": "stark-portal"})


if __name__ == "__main__":
    init_db()
    host = os.environ.get("STARK_HOST", "127.0.0.1")
    port = int(os.environ.get("STARK_PORT", "5050"))
    print(f"[+] Stark Portal (versión corregida) escuchando en http://{host}:{port}")
    app.run(host=host, port=port, debug=False)
