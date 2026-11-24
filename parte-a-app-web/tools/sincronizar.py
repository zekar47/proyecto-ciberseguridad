"""
Copia ORIGEN en DESTINO como espejo (equivalente a rsync -a --delete --exclude ...).
Los nombres excluidos no se copian ni se borran del destino.
Uso: python tools/sincronizar.py ORIGEN DESTINO [--exclude PATRON ...]
"""
import argparse
import shutil
from fnmatch import fnmatch
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("origen"); ap.add_argument("destino")
ap.add_argument("--exclude", action="append", default=[])
a = ap.parse_args()
src, dst = Path(a.origen).resolve(), Path(a.destino).resolve()
excl = a.exclude + [".git"]


def excluido(nombre):
    return any(fnmatch(nombre, p) for p in excl)


def espejo(s: Path, d: Path):
    d.mkdir(parents=True, exist_ok=True)
    nombres = {p.name for p in s.iterdir() if not excluido(p.name)}
    for p in d.iterdir():                      # borra lo que ya no existe en el origen
        if p.name not in nombres and not excluido(p.name):
            shutil.rmtree(p) if p.is_dir() and not p.is_symlink() else p.unlink()
    for n in sorted(nombres):
        sp, dp = s / n, d / n
        if sp.is_dir() and not sp.is_symlink():
            if dp.exists() and not dp.is_dir():
                dp.unlink()
            espejo(sp, dp)
        else:
            if dp.is_dir():
                shutil.rmtree(dp)
            shutil.copy2(sp, dp)


espejo(src, dst)
