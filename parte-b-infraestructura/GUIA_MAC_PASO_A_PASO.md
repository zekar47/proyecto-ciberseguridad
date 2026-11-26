# Guía paso a paso: MFA (TOTP) sobre SSH en `SRV-STARK-01`
### Mac con Apple Silicon (M1/M2/M3/M4) + VM Ubuntu Server en UTM

**Objetivo:** demostrar con capturas propias el **antes** (la cuenta privilegiada entra solo con contraseña) y el **después** (contraseña + código del teléfono), además de los intentos **denegados** y los **registros**.

**Necesitas:** la Mac, unos 8 GB libres en disco, Internet para descargar, y un **teléfono** con Aegis, FreeOTP o Google Authenticator. En **Android usa Aegis**: Google Authenticator bloquea las capturas de pantalla (en Aegis desactiva temporalmente Ajustes → Seguridad → «Seguridad de pantalla» y vuelve a activarla al terminar).

**Datos de laboratorio (ficticios):**

| Elemento | Valor |
|---|---|
| VM | `SRV-STARK-01` (Ubuntu Server 24.04 LTS ARM64) |
| Cuenta privilegiada | `ana.ti` (grupo `stark_ti`), con MFA |
| Cuenta operativa | `luis.oper` (grupo `stark_oper`), sin MFA |
| Estación TI | la propia Mac (Terminal) |
| IP de la VM | `192.168.64.X`: la anotas en el Paso 6 y la usas donde diga `IP_VM` |

> Convención: **[Mac]** = Terminal de la Mac. **[VM]** = consola de la VM en UTM, o una sesión SSH a la VM.
> Copia los comandos tal cual, uno por uno.
> **Regla de oro:** los `ssh ...` se escriben solo cuando el prompt empieza con tu usuario de la Mac (`tu_usuario@MacBook... %`). Si empieza con `ana.ti@srv-stark-01`, primero escribe `exit`.
> Si tu Mac tiene llaves SSH propias, agrega `-o PubkeyAuthentication=no` a los `ssh` para forzar contraseña + código.
> Usa la app **Terminal** de macOS: algunas terminales integradas no tienen permiso de «Red local» y fallan con `No route to host`.

---

## Fase 1 — Preparar la Mac

**Paso 1 — Instalar UTM (virtualizador gratuito para Apple Silicon)**
Descarga UTM desde https://mac.getutm.app y arrastra `UTM.app` a *Aplicaciones*.
**Resultado esperado:** UTM abre y muestra «Welcome to UTM».

**Paso 2 — Descargar Ubuntu Server para ARM**
Descarga desde https://ubuntu.com/download/server/arm el archivo `ubuntu-24.04.x-live-server-arm64.iso`.
**Resultado esperado:** el `.iso` (~2.5 GB) aparece en *Descargas*.

---

## Fase 2 — Levantar la VM `SRV-STARK-01`

**Paso 3 — Crear la VM**
En UTM, sigue *Create a New Virtual Machine* → **Virtualize** → **Linux** → *Boot ISO Image: Browse* (elige el `.iso`) → Memory **2048 MB**, CPU **2** → Storage **20 GB** → Shared Directory: ninguno → Name: **SRV-STARK-01** → **Save**.
**Resultado esperado:** la VM aparece en la lista de UTM. La red queda en *Shared Network*, que es la opción por defecto.

**Paso 4 — Instalar Ubuntu**
Presiona ▶ y elige *Try or Install Ubuntu Server*. Durante la instalación:
- Idioma English o Español; teclado **Spanish (Latin American)**.
- Red: deja DHCP. Proxy: vacío. Mirror: el sugerido. Disco: *Use an entire disk*.
- **Profile:** Your name `Ana TI` · Server name `srv-stark-01` · Username **`ana.ti`** · contraseña ficticia de laboratorio (anótala).
- **SSH:** marca ✅ **Install OpenSSH server**.
- Featured snaps: ninguno.

**Resultado esperado:** la instalación termina con «Installation complete!».

**Paso 5 — Expulsar el ISO y reiniciar**
En la barra de UTM, ve al ícono del CD → **Clear**, y luego elige *Reboot Now* en la VM.
**Resultado esperado:** la VM arranca y muestra `srv-stark-01 login:`.

**Paso 6 — [VM] Iniciar sesión como `ana.ti` y ver la IP**
```bash
ip -4 -br addr
```
**Resultado esperado:** una línea parecida a `enp0s1  UP  192.168.64.5/24`. **Anota esa IP**: es tu `IP_VM`.

---

## Fase 3 — Estado «antes»: SSH solo con contraseña

**Paso 7 — [VM] Crear el grupo privilegiado**
```bash
sudo groupadd stark_ti
```
**Resultado esperado:** no imprime nada (éxito).

**Paso 8 — [VM] Agregar `ana.ti` al grupo privilegiado**
```bash
sudo usermod -aG stark_ti ana.ti
```
**Resultado esperado:** no imprime nada.

**Paso 9 — [VM] Crear el grupo operativo**
```bash
sudo groupadd stark_oper
```
**Resultado esperado:** no imprime nada.

**Paso 10 — [VM] Crear la cuenta operativa**
```bash
sudo useradd -m -s /bin/bash -G stark_oper luis.oper
```
**Resultado esperado:** no imprime nada.

**Paso 11 — [VM] Asignar una contraseña ficticia a `luis.oper`**
```bash
sudo passwd luis.oper
```
**Resultado esperado:** `passwd: password updated successfully`.

**Paso 12 — [VM] Ver cómo autentica SSH hoy**
```bash
sudo sshd -T | grep -E '^(usepam|passwordauthentication|kbdinteractiveauthentication|authenticationmethods) '
```
**Resultado esperado:** `usepam yes`, `passwordauthentication yes` y `authenticationmethods any`.
📸 **Captura (ANTES):** la salida completa. Demuestra que el servidor acepta **solo contraseña** y que no exige ningún segundo factor.

**Paso 13 — [Mac] Abrir Terminal y entrar por SSH como `ana.ti`**
```bash
ssh ana.ti@IP_VM
```
**Resultado esperado:** la primera vez pregunta `Are you sure you want to continue connecting` → escribe `yes`. Luego pide `password:` y entras al prompt `ana.ti@srv-stark-01:~$`.

**Paso 14 — [Mac, dentro de la sesión] Mostrar quién eres**
```bash
id
```
**Resultado esperado:** `uid=1000(ana.ti) ... groups=...,1001(stark_ti)` (los números pueden variar).
📸 **Captura (ANTES):** toda la ventana, desde el `ssh` hasta el `id`. Hallazgo: la cuenta **privilegiada** entra con **solo la contraseña**; si esa contraseña se roba por phishing (T2), el atacante entra.

**Paso 15 — Salir de la sesión**
```bash
exit
```

---

## Fase 4 — Instalar el módulo TOTP

**Paso 16 — [Mac] Volver a entrar a la VM** (las fases siguientes se hacen desde esta sesión)
```bash
ssh ana.ti@IP_VM
```

**Paso 17 — [VM] Actualizar la lista de paquetes**
```bash
sudo apt update
```
**Resultado esperado:** termina con `Reading package lists... Done`.

**Paso 18 — [VM] Instalar el módulo PAM de Google Authenticator**
```bash
sudo apt install -y libpam-google-authenticator
```
**Resultado esperado:** `Setting up libpam-google-authenticator ...` sin errores.

---

## Fase 5 — Enrolar a `ana.ti` con el teléfono

> Antes de este paso, maximiza la ventana de Terminal y reduce la letra con **Cmd −** para que el código QR quepa completo.

**Paso 19 — [VM] Generar el secreto TOTP de `ana.ti`**
```bash
google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 5 -Q UTF8
```
(`-t` códigos por tiempo · `-d` prohíbe reutilizar un código · `-r 3 -R 30` máximo 3 intentos cada 30 s · `-w 3` tolera ±30 s de desfase de reloj · `-e 5` cinco códigos de emergencia)
**Resultado esperado:** aparece un **código QR**, la línea `Your new secret key is: ...` y luego `Enter code from app (-1 to skip):`.

**Paso 20 — [Teléfono] Escanear el QR**
En la app autenticadora toca **+** → *Escanear código QR* y apunta al QR de la Terminal.
**Resultado esperado:** la app muestra una entrada `ana.ti@srv-stark-01` con un código de 6 dígitos que cambia cada 30 s.

**Paso 21 — [VM] Confirmar el código**
Escribe en la Terminal el código que muestra la app y presiona Enter.
**Resultado esperado:** `Code confirmed` y luego `Your emergency scratch codes are:` con 5 códigos de 8 dígitos.
📸 **Captura (DESPUÉS — enrolamiento):** la ventana con el QR y los códigos. **Antes de pegarla en el informe, tapa el QR, la secret key y los códigos de emergencia** (por ejemplo, con Vista Previa → Herramientas → Rectángulo relleno). Demuestra que el segundo factor quedó ligado a un dispositivo físico.

**Paso 22 — Guardar los códigos de emergencia**
Copia los 5 códigos en papel. Cada uno sirve **una sola vez** si pierdes el teléfono.

**Paso 23 — [VM] Verificar que el secreto está protegido**
```bash
ls -l ~/.google_authenticator
```
**Resultado esperado:** `-r-------- 1 ana.ti ana.ti ...`, es decir, solo `ana.ti` puede leerlo.

---

## Fase 6 — Exigir el segundo factor en PAM y SSH

> ⚠️ **No cierres esta sesión SSH hasta el Paso 31.** Si algo falla, puedes entrar desde la consola de la VM en UTM, porque el login local no pasa por SSH.

**Paso 24 — [VM] Respaldar la configuración de PAM de SSH**
```bash
sudo cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
```
**Resultado esperado:** no imprime nada.

**Paso 25 — [VM] Editar PAM de SSH**
```bash
sudo nano /etc/pam.d/sshd
```
Justo **debajo** de la línea `@include common-auth`, pega estas 4 líneas:
```
# STARK-MFA inicio: segundo factor (TOTP) solo para el grupo privilegiado stark_ti
auth [success=1 default=ignore] pam_succeed_if.so user notingroup stark_ti quiet
auth required pam_google_authenticator.so
# STARK-MFA fin
```
Guarda con **Ctrl+O**, **Enter** y sal con **Ctrl+X**.
**Resultado esperado:** vuelves al prompt. (La línea `pam_succeed_if` salta el código a quien **no** esté en `stark_ti`.)

**Paso 26 — [VM] Crear la configuración de SSH para MFA**
```bash
sudo nano /etc/ssh/sshd_config.d/10-stark-mfa.conf
```
Pega:
```
# STARK-MFA: la autenticacion pasa por PAM (contrasena + codigo TOTP)
UsePAM yes
KbdInteractiveAuthentication yes
PasswordAuthentication no
AuthenticationMethods keyboard-interactive
```
Guarda (**Ctrl+O**, **Enter**, **Ctrl+X**).
**Resultado esperado:** vuelves al prompt. El nombre `10-...` hace que se lea antes que `50-cloud-init.conf`, que en Ubuntu activa `PasswordAuthentication yes`.

**Paso 27 — [VM] Validar la sintaxis de SSH**
```bash
sudo sshd -t
```
**Resultado esperado:** **no imprime nada**. Si muestra un error, revisa el Paso 26.

**Paso 28 — [VM] Reiniciar SSH**
```bash
sudo systemctl restart ssh
```
**Resultado esperado:** no imprime nada. Tu sesión actual sigue abierta.

**Paso 29 — [VM] Ver la configuración nueva**
```bash
sudo sshd -T | grep -E '^(usepam|passwordauthentication|kbdinteractiveauthentication|authenticationmethods) '
```
**Resultado esperado:** `passwordauthentication no` y `authenticationmethods keyboard-interactive`.
📸 **Captura (DESPUÉS — configuración):** esta salida junto con la del Paso 12. Demuestra el cambio de «solo contraseña» a «autenticación por PAM con segundo factor».

**Paso 30 — [VM] Mostrar las líneas agregadas a PAM**
```bash
sed -n '/STARK-MFA inicio/,/STARK-MFA fin/p' /etc/pam.d/sshd
```
**Resultado esperado:** las 4 líneas del Paso 25.
📸 **Captura (DESPUÉS — configuración):** evidencia del control implementado.

---

## Fase 7 — Validar: antes vs. después y accesos denegados

**Paso 31 — [Mac] Abrir una ventana NUEVA de Terminal (Cmd+N) y entrar como `ana.ti`**
```bash
ssh ana.ti@IP_VM
```
**Resultado esperado:** pide `Password:` y después **`Verification code:`**. Escribe el código de la app y entras.
📸 **Captura (DESPUÉS):** la ventana con ambas preguntas y el prompt. Hallazgo: la contraseña **ya no basta**; se necesita además el teléfono.

**Paso 32 — Salir**
```bash
exit
```

**Paso 33 — [Mac] Simular una contraseña robada (código inventado)**
```bash
ssh ana.ti@IP_VM
```
Escribe la contraseña **correcta** y en `Verification code:` escribe `000000`.
**Resultado esperado:** no entra: el servidor vuelve a pedir `Password:` (tras 3 intentos termina con `Permission denied (keyboard-interactive).`). Corta con **Ctrl+C**. En `auth.log` queda `Invalid verification code for ana.ti`.
📸 **Captura (DESPUÉS — denegado):** Hallazgo: **una credencial robada por phishing no basta** (mitiga T2 y T6).

**Paso 34 — [Mac] Intentar reutilizar un código (repetición)**
Entra con contraseña y el código actual (`ssh ana.ti@IP_VM`), ejecuta `exit` y **en menos de 30 segundos** vuelve a entrar con **el mismo código**:
```bash
ssh ana.ti@IP_VM
```
**Resultado esperado:** con el código repetido no entra y vuelve a pedir `Password:`; en `auth.log` aparece `Trying to reuse a previously used time-based code`. Truco: tras el `exit`, presiona **↑** y Enter para repetir el `ssh` rápido.
📸 **Captura (DESPUÉS — denegado):** demuestra que un código interceptado no se puede reutilizar (opción `-d`).

**Paso 35 — [Mac] Entrar con un código de emergencia** (simula un teléfono perdido)
```bash
ssh ana.ti@IP_VM
```
En `Verification code:` escribe **uno** de los códigos de emergencia.
**Resultado esperado:** entras. Si repites ese mismo código otra vez, `Permission denied`, porque es de un solo uso.
📸 **Captura (DESPUÉS, opcional):** demuestra que hay un plan de recuperación del acceso sin desactivar el MFA.

**Paso 36 — [Mac] Comprobar que el perfil operativo no se afectó**
```bash
ssh luis.oper@IP_VM
```
**Resultado esperado:** pide solo `Password:` y entras sin código.
📸 **Captura (DESPUÉS):** demuestra que el MFA se aplica **solo al perfil privilegiado**, como se diseñó.

---

## Fase 8 — Registros (detección)

**Paso 37 — [VM] Revisar los eventos de autenticación**
```bash
sudo grep -E 'Accepted|Invalid verification|reuse a previously|Authentication failure' /var/log/auth.log | tail -20
```
**Resultado esperado:** líneas `Accepted google_authenticator for ana.ti`, `Invalid verification code for ana.ti`, `Trying to reuse a previously used time-based code` y `Accepted keyboard-interactive/pam for luis.oper`.
(Si `/var/log/auth.log` no existe, usa `sudo journalctl -u ssh --since today`.)
📸 **Captura (DESPUÉS — registros):** demuestra que cada intento queda registrado con usuario, IP y hora, lo que sirve para detectar un ataque.

---

## Fase 9 — Refuerzo opcional: SSH solo desde la Estación TI

**Paso 38 — [VM] Permitir SSH solo desde la Mac** (en la red *Shared* de UTM, la Mac es `192.168.64.1`)
```bash
sudo ufw allow from 192.168.64.1 to any port 22 proto tcp
```
**Resultado esperado:** `Rules updated`.

**Paso 39 — [VM] Activar el firewall**
```bash
sudo ufw enable
```
**Resultado esperado:** `Firewall is active and enabled on system startup` (escribe `y` si pregunta).

**Paso 40 — [VM] Ver las reglas**
```bash
sudo ufw status numbered
```
**Resultado esperado:** `22/tcp ALLOW IN 192.168.64.1`.
📸 **Captura (DESPUÉS — refuerzo):** SSH solo es accesible desde la zona de administración (regla R3 del avance), y además exige MFA.

---

## Si te quedas fuera (recuperación)

En la consola de la VM en UTM (login local), ejecuta:
```bash
sudo cp /etc/pam.d/sshd.bak /etc/pam.d/sshd
```
```bash
sudo rm /etc/ssh/sshd_config.d/10-stark-mfa.conf
```
```bash
sudo systemctl restart ssh
```
