"""
Toma capturas reales de la app con el Chrome instalado (Playwright, modo headless).
Si ZAP está corriendo, la navegación pasa por su proxy para que registre las
peticiones (equivale a la "exploración manual" de ZAP).

Uso: python tools/capturas.py [--zap http://127.0.0.1:8090]
"""
import argparse
from pathlib import Path

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5050"
OUT = Path(__file__).resolve().parent.parent / "evidencias" / "capturas"
OUT.mkdir(parents=True, exist_ok=True)

ap = argparse.ArgumentParser()
ap.add_argument("--zap", default=None, help="URL del proxy de ZAP")
ap.add_argument("--channel", default="chrome")
args = ap.parse_args()

launch = {"headless": True, "channel": args.channel}
if args.zap:
    # <-loopback> hace que Chrome sí mande 127.0.0.1 por el proxy
    launch["proxy"] = {"server": args.zap, "bypass": "<-loopback>"}
    launch["args"] = ["--proxy-bypass-list=<-loopback>"]


def foto(page, nombre, full=False):
    ruta = OUT / f"{nombre}.png"
    page.screenshot(path=str(ruta), full_page=full)
    print(f"  captura -> {ruta.relative_to(OUT.parent.parent)}")


with sync_playwright() as p:
    browser = p.chromium.launch(**launch)
    ctx = browser.new_context(viewport={"width": 1280, "height": 520}, ignore_https_errors=True)
    page = ctx.new_page()

    page.goto(f"{BASE}/salud")
    foto(page, "a1_salud")

    page.goto(f"{BASE}/dashboard")          # sin sesión -> redirige a /login
    foto(page, "a2_login_redireccion")

    page.fill("input[name=username]", "luis.oper")
    page.fill("input[name=password]", "Turno1!2026")
    foto(page, "a3_login_formulario")
    page.click("button[type=submit]")
    page.wait_for_url("**/dashboard")
    foto(page, "a4_dashboard")

    page.goto(f"{BASE}/buscar?q=buje")
    foto(page, "a5_catalogo")

    page.goto(f"{BASE}/comentarios")
    page.fill("textarea[name=texto]", "Prueba de funcionamiento del tablero (Actividad 1).")
    page.click("button[type=submit]")
    foto(page, "a6_avisos")

    page.goto(f"{BASE}/perfil/2")
    foto(page, "a7_perfil")

    page.goto(f"{BASE}/api/ordenes/2")
    foto(page, "a8_api_ordenes")

    browser.close()
print("Capturas listas.")
