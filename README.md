# sysadmin-scripts

Colección de scripts y configuraciones para tareas habituales de **administración de sistemas**: gestión de usuarios en Active Directory, copias de seguridad, revisión del estado de servidores y monitorización de servicios.

Todos los scripts están comentados paso a paso y gestionan los errores con códigos de salida, para poder programarlos con `cron` o con el Programador de tareas y supervisarlos.

## Contenido

| Script | Plataforma | Qué hace |
|---|---|---|
| [`powershell/New-ADUsersFromCsv.ps1`](powershell/New-ADUsersFromCsv.ps1) | Windows Server | Alta masiva de usuarios en Active Directory desde un CSV |
| [`bash/backup.sh`](bash/backup.sh) | Linux | Copia de seguridad `.tar.gz` con verificación, rotación y log |
| [`bash/healthcheck.sh`](bash/healthcheck.sh) | Linux | Revisión del disco, la RAM, la CPU y los servicios, con umbrales de alerta |
| [`docker/uptime-kuma/`](docker/uptime-kuma/docker-compose.yml) | Docker | Panel de monitorización de disponibilidad de webs y servidores |

---

### 1. Alta masiva de usuarios en Active Directory

Automatiza el alta de empleados nuevos a partir de un CSV (`Nombre;Apellido;Departamento;Puesto`):

- Genera el usuario con el formato *inicial + apellido* (`lmartinez`) y quita acentos y caracteres especiales.
- Comprueba si el usuario ya existe para no duplicarlo.
- Lo crea en la **OU de su departamento**, con una contraseña temporal aleatoria que cumple la directiva de complejidad y la obligación de **cambiarla en el primer inicio de sesión**.
- Lo añade al **grupo de seguridad** del departamento (`GRP_Ventas`, `GRP_IT`…).
- Admite `-WhatIf` para simular la ejecución sin tocar nada.

```powershell
# Simulación (no crea nada)
.\New-ADUsersFromCsv.ps1 -CsvPath .\usuarios_ejemplo.csv -BaseOU "OU=Empresa,DC=empresa,DC=local" -WhatIf

# Ejecución real
.\New-ADUsersFromCsv.ps1 -CsvPath .\usuarios_ejemplo.csv -BaseOU "OU=Empresa,DC=empresa,DC=local"
```

Requiere el módulo `ActiveDirectory` (RSAT) y permisos de creación de usuarios en el dominio.

### 2. Copias de seguridad con rotación

```bash
./bash/backup.sh /etc /srv/backups 7     # copia /etc y conserva 7 días
```

- Comprueba antes de empezar que hay **espacio suficiente** en el destino.
- **Verifica** que el `.tar.gz` generado no está corrupto.
- **Rotación:** borra las copias con más de *N* días.
- Registra todo en `/var/log/backup.log` y devuelve un código de error distinto para cada fallo.

Programado con cron, todos los días a las 3:00:

```cron
0 3 * * * /opt/scripts/backup.sh /etc /srv/backups 7
```

### 3. Healthcheck de servidor Linux

```bash
./bash/healthcheck.sh
UMBRAL_DISCO=90 SERVICIOS="ssh nginx" ./bash/healthcheck.sh
```

Revisa el uso de **disco**, **RAM** y **carga de CPU** frente a umbrales configurables, y comprueba que los **servicios systemd** indicados estén activos. Devuelve `0` si todo está bien y `1` si hay alertas, así que se puede integrar en cron o en herramientas como Zabbix o Nagios.

### 4. Monitorización con Uptime Kuma (Docker)

```bash
cd docker/uptime-kuma
docker compose up -d        # panel en http://localhost:3001
```

Comprueba periódicamente si las webs, servidores o puertos responden (HTTP, ping, TCP, DNS) y avisa por Telegram o email cuando algo cae. Los datos persisten en un volumen de Docker y el contenedor se reinicia solo (`restart: unless-stopped`).

---

## Cómo se han probado

- Los scripts de Bash se han validado con **ShellCheck** sin avisos y se han probado en Linux, incluidos los casos de error (origen inexistente y rotación de copias antiguas).
- El `docker-compose.yml` se ha validado con `docker compose config`.
- El script de PowerShell está pensado para un laboratorio con **Windows Server + Active Directory** (máquina virtual) como el del CFGS ASIX. Pruébalo siempre primero con `-WhatIf`.

---

[Toni Susany](https://github.com/uabtoni) · Técnico de sistemas y redes
