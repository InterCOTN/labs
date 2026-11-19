# COTN 2150 · Servidor de práctica de los laboratorios

Cada carpeta `module-NN/` tiene el script `lab_server_setup.sh` que prepara la VM de práctica (Ubuntu 24.04) del laboratorio de ese módulo. Las instrucciones del laboratorio están en Blackboard.

```bash
sudo bash lab_server_setup.sh     # dentro de la VM de práctica, nunca en su computadora principal
```

| Módulo | Qué prepara |
|---|---|
| 4 | SSH, nginx, cuenta `lab` sin sudo y carpeta `/var/www/portal` |
| 5 | SSH y cuenta `lab` con sudo (el laboratorio instala el resto) |
| 6 | SSH, Apache, PHP y MySQL (el laboratorio instala WordPress) |
| 7 | SSH y cuenta `lab` (el laboratorio instala FTP y correo) |
| 8 | SSH, Apache, Postfix solo local, cuentas de práctica; `comprobar.sh` y `alerta.sh` |
| 9 | Igual que el 8, para el laboratorio de licencias y ética |
| 10 | Igual que el 8, para el laboratorio integrador (también lo usa el caso A1) |

Las contraseñas de los scripts son valores de entrenamiento válidos solo en esa VM.
