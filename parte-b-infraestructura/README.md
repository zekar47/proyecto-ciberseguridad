# Stark Manufactura — Proyecto final de Ciberseguridad, Parte B

**Mejora elegida:** Opción D, autenticación y control de acceso. Se exige un **segundo factor TOTP** en el SSH de `SRV-STARK-01` a la cuenta privilegiada (grupo `stark_ti`), con `libpam-google-authenticator`.
**Refuerzo:** SSH accesible solo desde Administración. En la VM de la Mac se aplicó con `ufw` (22/tcp solo desde la Estación TI); la versión completa con nftables está en la carpeta `firewall/` (Anexo A del informe).

Todas las cuentas, contraseñas, IPs y datos son **ficticios de laboratorio**. El repositorio no contiene secretos TOTP ni contraseñas.

## MFA en SSH (mejora principal)

Para seguir el proceso desde cero en una Mac con Apple Silicon (VM Ubuntu en UTM + teléfono), usa **[GUIA_MAC_PASO_A_PASO.md](GUIA_MAC_PASO_A_PASO.md)**.

Si ya tienes un servidor Ubuntu/Debian con OpenSSH, primero enrola al usuario privilegiado (como ese usuario) y escanea el QR con la app:

```bash
google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 5 -Q UTF8
```

Aplica la MFA. El script respalda PAM, crea el drop-in de SSH y valida con `sshd -t`:

```bash
sudo ./mfa/configurar_mfa.sh
```

Revisa los inicios aceptados, los códigos inválidos y las reutilizaciones:

```bash
sudo ./mfa/ver_registros_ssh.sh
```

Para volver a solo contraseña:

```bash
sudo ./mfa/revertir_mfa.sh
```

> Mantén abierta una sesión SSH mientras pruebas, para no quedarte fuera.
>
> Si al ejecutar un script aparece `Permission denied`, dale permiso de ejecución una vez: `chmod +x mfa/*.sh firewall/*.sh pruebas/*.sh` (o ejecútalo con `sudo bash mfa/configurar_mfa.sh`). `configurar_mfa.sh` y `revertir_mfa.sh` se probaron en la VM Ubuntu 24.04.5 real.

`mfa/lab/` contiene ayudas **solo de laboratorio** (enrolamiento sin intervención y app autenticadora simulada con `oathtool`), útiles para pruebas automáticas. **Las capturas de `evidencias/capturas_mfa/` NO salen de ahí**: son de la ejecución real descrita abajo.

### Ejecución real (evidencias)

| Elemento | Valor |
|---|---|
| Equipo | Mac con Apple Silicon |
| `SRV-STARK-01` | VM Ubuntu Server 24.04.5 LTS ARM64 en UTM, 192.168.64.5, OpenSSH 9.6p1, `libpam-google-authenticator` 20191231 |
| Estación TI | la propia Mac, 192.168.64.1 (red *Shared* de UTM) |
| Segundo factor | teléfono Android real con **Aegis Authenticator** |
| Cuentas | `ana.ti` (`stark_ti`, con MFA) y `luis.oper` (`stark_oper`, sin MFA) |

Notas de la ejecución:

- La VM se creó con la imagen oficial *cloud* de Ubuntu 24.04 ARM64 y cloud-init (en lugar del instalador ISO); el resultado es el mismo Ubuntu Server con OpenSSH.
- Para administrar la VM sin escribir contraseñas se usó una cuenta **solo de laboratorio**, `labadmin`, que entra con llave SSH gracias a `/etc/ssh/sshd_config.d/90-lab-admin.conf` (`Match User labadmin` → `AuthenticationMethods publickey`). En producción no debe existir una excepción así.
- El enrolamiento se ejecutó como `ana.ti` (`sudo -iu ana.ti google-authenticator ...`); el archivo quedó como propiedad de `ana.ti` con permisos `-r--------`.
- `mfa/ver_registros_ssh.sh` se corrigió para ignorar las líneas de `sudo` que solo mencionan `sshd` (inflaban los conteos).


## Refuerzo: firewall nftables

| Regla | Origen | Servicio | Acción |
|---|---|---|---|
| R0 | Equipo en cuarentena | Cualquiera | Bloquear y registrar |
| R3 | Administración (192.168.56.130) | SSH 22 | Permitir y registrar |
| R1 | Usuarios (192.168.56.110) y Administración | SMB 139/445 | Permitir |
| R4 | Cualquier otro | SSH 22 | Bloquear y registrar |
| DB | Cualquiera | MariaDB 3306 | Bloquear y registrar |
| R9 | Cualquiera | Todo lo demás | Bloquear y registrar (denegación por defecto) |

Todas las IPs, cuentas y datos son **ficticios de laboratorio**. El repositorio no contiene credenciales.

## Requisitos

- **Servidor** (host Linux con la IP 192.168.56.1 en la red host-only, p. ej. Arch): `nftables`, y de forma opcional `conntrack`.
- **Estación de auditoría** (Kali en la misma red host-only): `nmap` y `netcat`.

## Ejecución

En **Kali**, para obtener la línea base sin firewall:

```bash
sudo ./pruebas/pruebas_kali.sh antes
```

En el **servidor**, para aplicar el firewall (detecta solo la interfaz de 192.168.56.1, normalmente `vboxnet0`):

```bash
sudo ./firewall/aplicar_firewall.sh
```

En **Kali**, para validar:

```bash
sudo ./pruebas/pruebas_kali.sh despues
```

En el **servidor**, para revisar los eventos registrados:

```bash
sudo ./firewall/ver_registros.sh "30 min ago"
```

Para la contención de incidentes (cuarentena de un equipo):

```bash
sudo ./firewall/cuarentena.sh agregar 192.168.56.110 2h
```

```bash
sudo ./firewall/cuarentena.sh quitar 192.168.56.110
```

Para retirar el firewall al terminar:

```bash
sudo ./firewall/revertir_firewall.sh
```

`pruebas_kali.sh` agrega a la interfaz de Kali las IPs de rol (.110 = Usuarios, .130 = Administración). Después ejecuta la matriz P1–P8 con `nc` y un Nmap por rol, y guarda todo en `resultados_<etiqueta>/`.

El firewall solo filtra el tráfico que entra por la interfaz del laboratorio. El Wi-Fi y el loopback del host no se ven afectados. Las reglas no son persistentes: se pierden al reiniciar o con `revertir_firewall.sh`.

## Evidencias

- `evidencias/capturas_mfa/`: Figuras 1–10 de la MFA y 4b/5b del teléfono (PNG de la ejecución real en la Mac, y salida en texto con las líneas de `auth.log`). El QR, la clave secreta y los códigos de emergencia están tapados u omitidos.
- `evidencias/capturas/`: Figuras A1–A10 del firewall (PNG y salida en texto).
- `evidencias/laboratorio/`: matriz y escaneos Nmap (`-oN`) antes y después.
- `evidencias/simulacion_namespaces/`: primera validación de las reglas con servicios de prueba.

## Archivos del avance (referencia)

- `avance/diagramas/STARK_diagramas_red.drawio`: red actual (plana) y red propuesta (VLAN 10/20/30 + DMZ). Las reglas de `firewall/stark_fw.nft` implementan, sobre `SRV-STARK-01`, el diseño de la red propuesta.
- `avance/gophish/`: configuración y resultados exportados de la simulación de phishing (plantilla, landing page, perfil de envío a MailHog, campaña y `config.json`). Los destinatarios son ficticios (`*.stark.lab`) y la landing page no captura contraseñas (`capture_passwords: false`).
