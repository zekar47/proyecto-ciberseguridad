"""
Stark Manufactura — Portal Interno, aplicación INTENCIONALMENTE VULNERABLE.

Uso exclusivo en laboratorio local para el Proyecto Final de Ciberseguridad
(Tecmilenio). Contiene tres vulnerabilidades a propósito:

  [VULN-1] SQL Injection ........ /login  y  /buscar
  [VULN-2] Cross-Site Scripting . /buscar (reflejado)  y  /comentarios (almacenado)
  [VULN-3] IDOR / BOLA .......... /perfil/<id>  y  /api/ordenes/<id>

Cada punto vulnerable está marcado en el código con "# VULN-x".
NO desplegar en internet ni en una red compartida. Todos los datos son ficticios.
"""
import logging
import os
import sqlite3
from functools import wraps
from pathlib import Path

from flask import (Flask, g, jsonify, redirect, render_template, request,
                   session, url_for)

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "stark.db"
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)

app = Flask(__name__)
# Clave sólo para laboratorio. Se puede sobreescribir con la variable STARK_SECRET.
app.secret_key = os.environ.get("STARK_SECRET", "clave-de-laboratorio-no-usar-en-produccion")

# ---------------------------------------------------------------------------
# Registro de eventos (útil para la Actividad 5)
# ---------------------------------------------------------------------------
logging.basicConfig(
    filename=LOG_DIR / "app.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("stark")


@app.after_request
def registrar_peticion(resp):
    log.info(
        "ip=%s usuario=%s metodo=%s ruta=%s estado=%s",
        request.remote_addr,
        session.get("username", "-"),
        request.method,
        request.full_path.rstrip("?"),
        resp.status_code,
    )
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


def init_db():
    """Crea la base de datos con datos ficticios (se reinicia en cada arranque)."""
    if DB_PATH.exists():
        DB_PATH.unlink()
    con = sqlite3.connect(DB_PATH)
    con.executescript(
        """
        CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,          -- en texto plano a propósito (laboratorio)
            nombre TEXT NOT NULL,
            puesto TEXT NOT NULL,
            correo TEXT NOT NULL,
            telefono TEXT NOT NULL,
            rol TEXT NOT NULL
        );
        CREATE TABLE productos (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            categoria TEXT NOT NULL,
            precio REAL NOT NULL
        );
        CREATE TABLE reportes (
            id INTEGER PRIMARY KEY,
            usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
            titulo TEXT NOT NULL,
            contenido TEXT NOT NULL,
            clasificacion TEXT NOT NULL
        );
        CREATE TABLE comentarios (
            id INTEGER PRIMARY KEY,
            autor TEXT NOT NULL,
            texto TEXT NOT NULL,
            fecha TEXT DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO usuarios VALUES
          (1,'ana.ti','TI#Stark2026','Ana Torres','Administradora de TI','ana.torres@stark.example','81-0000-0001','stark_ti'),
          (2,'luis.oper','Turno1!2026','Luis Méndez','Operador CNC','luis.mendez@stark.example','81-0000-0002','stark_oper'),
          (3,'sofia.consulta','Consulta*26','Sofía Ramos','Analista de compras','sofia.ramos@stark.example','81-0000-0003','stark_consulta'),
          (4,'mgarza.rh','RH-Garza-26','María Garza','Recursos Humanos','maria.garza@stark.example','81-0000-0004','stark_consulta');

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
    con.commit()
    con.close()


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def login_requerido(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    if "user_id" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")

        # VULN-1 (SQL Injection): la consulta se arma concatenando la entrada
        # del usuario. Un valor como  admin' --  comenta la validación de la
        # contraseña y permite entrar sin conocerla.
        query = (
            f"SELECT id, username, nombre, rol FROM usuarios "
            f"WHERE username = '{username}' AND password = '{password}'"
        )
        log.info("consulta_login=%s", query)
        try:
            user = get_db().execute(query).fetchone()
        except sqlite3.Error as e:
            log.warning("error_sql_login=%s", e)
            # Mostrar el error de la base de datos también es una mala práctica
            error = f"Error de base de datos: {e}"
            user = None

        if user:
            session["user_id"] = user["id"]
            session["username"] = user["username"]
            session["nombre"] = user["nombre"]
            session["rol"] = user["rol"]
            log.info("login_exitoso usuario=%s", user["username"])
            return redirect(url_for("dashboard"))
        if not error:
            log.warning("login_fallido usuario_ingresado=%s", username)
            error = "Usuario o contraseña incorrectos."
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
    q = request.args.get("q", "")
    resultados, error = [], None
    if q:
        # VULN-1 (SQL Injection): búsqueda concatenada. Con UNION SELECT se
        # pueden extraer datos de otras tablas (p. ej. usuarios y contraseñas).
        query = (
            f"SELECT nombre, categoria, precio FROM productos "
            f"WHERE nombre LIKE '%{q}%'"
        )
        log.info("consulta_busqueda=%s", query)
        try:
            resultados = get_db().execute(query).fetchall()
        except sqlite3.Error as e:
            log.warning("error_sql_busqueda=%s", e)
            error = f"Error de base de datos: {e}"
    # VULN-2 (XSS reflejado): la plantilla imprime q con el filtro |safe
    return render_template("buscar.html", q=q, resultados=resultados, error=error)


@app.route("/comentarios", methods=["GET", "POST"])
@login_requerido
def comentarios():
    db = get_db()
    if request.method == "POST":
        texto = request.form.get("texto", "")
        # VULN-2 (XSS almacenado): el texto se guarda sin validar y luego se
        # muestra con |safe, por lo que cualquier <script> se ejecuta en el
        # navegador de todos los que abran la página.
        db.execute(
            "INSERT INTO comentarios (autor, texto) VALUES (?, ?)",
            (session["username"], texto),
        )
        db.commit()
        return redirect(url_for("comentarios"))
    filas = db.execute("SELECT autor, texto, fecha FROM comentarios ORDER BY id DESC").fetchall()
    return render_template("comentarios.html", comentarios=filas)


@app.route("/perfil/<int:user_id>")
@login_requerido
def perfil(user_id):
    # VULN-3 (IDOR): sólo se verifica que haya sesión, NO que el perfil
    # solicitado pertenezca al usuario. Cambiando el número en la URL se ven
    # los datos personales de cualquier empleado.
    u = get_db().execute(
        "SELECT id, username, nombre, puesto, correo, telefono, rol FROM usuarios WHERE id = ?",
        (user_id,),
    ).fetchone()
    if not u:
        return render_template("mensaje.html", titulo="No encontrado", texto="El perfil no existe."), 404
    return render_template("perfil.html", u=u)


@app.route("/api/ordenes/<int:reporte_id>")
@login_requerido
def api_reporte(reporte_id):
    # VULN-3 (BOLA): la API devuelve cualquier orden de trabajo por su id sin validar
    # que reportes.usuario_id == usuario en sesión.
    r = get_db().execute(
        "SELECT id, usuario_id, titulo, contenido, clasificacion FROM reportes WHERE id = ?",
        (reporte_id,),
    ).fetchone()
    if not r:
        return jsonify({"error": "no encontrado"}), 404
    return jsonify(dict(r))


@app.route("/salud")
def salud():
    """Endpoint simple para verificar que el servicio está arriba (Actividad 1)."""
    return jsonify({"estado": "ok", "servicio": "stark-portal"})


if __name__ == "__main__":
    init_db()
    # Por seguridad sólo escucha en la máquina local. Para analizarla desde la VM
    # de Kali por la red host-only, usar STARK_HOST=192.168.56.1 (nunca 0.0.0.0
    # en una red compartida o pública).
    host = os.environ.get("STARK_HOST", "127.0.0.1")
    port = int(os.environ.get("STARK_PORT", "5050"))
    print(f"[!] App intencionalmente vulnerable escuchando en http://{host}:{port}")
    app.run(host=host, port=port, debug=False)
