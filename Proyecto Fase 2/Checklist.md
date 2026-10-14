# Checklist — Proyecto 2: Respaldo y Restauración (SQL Server)

**Entrega: 17-octubre-2026** · Todos los integrantes suben a **UEDI** (si alguien no sube, nota de cero).
**Regla general:** toda captura debe mostrar **fecha y hora del sistema operativo**. Todo backup/restore se ejecuta **por consola** (`sqlcmd` / PowerShell), nunca con la interfaz gráfica.

> **Pendiente de confirmar con el auxiliar:** la rúbrica dice "3 respaldos completos y 3 incrementales", pero la Fase 3 dice restaurar "los 3 backups incrementales" por tipo de carga. Este checklist asume **1 full + 3 diferenciales por cada tipo de carga** (3 fulls y 9 diferenciales en total).

---

## 0. Fase 1 — Preparación y diseño (en equipo, los 3 juntos)

- [ ] Levantar SQL Server 2022 Developer en Docker, con volumen persistente para `/var/opt/mssql/backups`
- [ ] Verificar que los 3 se conectan por `sqlcmd`
- [ ] Acordar la convención de nombres de archivos de respaldo
  - `full_<tipo>.bak` → ej. `full_anio.bak`
  - `diff_<tipo>_<n>.bak` → ej. `diff_anio_1.bak`
- [ ] Acordar qué ediciones, evento y atleta se usarán
  - Año: París 2024, Tokio 2020, Río 2016
  - Deporte: 100 m planos femeninos en esas mismas ediciones
  - Deportista: Usain Bolt en Atenas 2004, Pekín 2008, Londres 2012
- [ ] Verificar que esos datos existen en el dataset (Atenas 2004, Pekín 2008 y Londres 2012 vienen de `athlete_events`/`resultsFull`; París 2024 solo viene de `olympics_dataset`)
- [ ] Crear el repositorio Git con las carpetas `/ddl`, `/carga`, `/backup`, `/restauracion`, `/capturas`, `/docs`
- [ ] Subir el DDL del Proyecto 1 (esquema normalizado) y los CSV a cargar
- [ ] Crear la plantilla compartida de tiempos (ver sección 5)
- [ ] Repartir los entregables secundarios (ver sección 4)

---

## 1. Pablo — Carga por AÑO

**Datos:** París 2024 (carga inicial) → Tokio 2020 (carga 2) → Río 2016 (carga 3)

### Carga inicial + full
- [ ] Crear instancia/base de datos nueva y vacía (solo DDL)
- [ ] `BULK INSERT` de la edición 1 (París 2024)
- [ ] Captura: `SELECT *` de cada tabla (fecha/hora visible)
- [ ] Captura: `SELECT COUNT(*)` de cada tabla
- [ ] Captura: fragmentación de tablas (`sys.dm_db_index_physical_stats`)
- [ ] `BACKUP DATABASE` full → `full_anio.bak` (guardar el log de consola)

### Carga 2 + diferencial 1
- [ ] `BULK INSERT` de la edición 2 (Tokio 2020)
- [ ] Capturas: `SELECT *`, `COUNT(*)` y fragmentación
- [ ] `BACKUP DATABASE ... WITH DIFFERENTIAL` → `diff_anio_1.bak`

### Carga 3 + diferencial 2
- [ ] `BULK INSERT` de la edición 3 (Río 2016)
- [ ] Capturas: `SELECT *`, `COUNT(*)` y fragmentación
- [ ] `BACKUP DATABASE ... WITH DIFFERENTIAL` → `diff_anio_2.bak`

### Carga 4 + diferencial 3 (para llegar a los 3 diferenciales)
- [ ] Una carga adicional (otra edición, por ejemplo Londres 2012)
- [ ] Capturas: `SELECT *`, `COUNT(*)` y fragmentación
- [ ] `BACKUP DATABASE ... WITH DIFFERENTIAL` → `diff_anio_3.bak`

### Eliminar y restaurar
- [ ] Anotar los conteos finales de cada tabla antes de borrar
- [ ] `DROP DATABASE` (captura)
- [ ] Restaurar **solo el full**, midiendo el tiempo → anotar en la tabla de tiempos
- [ ] Captura: `SELECT *` y `COUNT(*)` tras el restore del full
- [ ] Eliminar la base otra vez
- [ ] Restaurar **full + diferencial 1**, midiendo el tiempo → anotar
- [ ] Capturas de validación
- [ ] Eliminar la base otra vez
- [ ] Restaurar **full + diferencial 2**, midiendo el tiempo → anotar
- [ ] Capturas de validación
- [ ] Eliminar la base otra vez
- [ ] Restaurar **full + diferencial 3**, midiendo el tiempo → anotar
- [ ] Capturas de validación: los conteos deben coincidir con los anotados antes de borrar

### Cierre
- [ ] Guardar scripts y logs en el repositorio
- [ ] Llenar la tabla de tiempos de "Año" (sección 5)

---

## 2. José — Carga por DEPORTE

**Datos:** 100 m planos femeninos en París 2024 → Tokio 2020 → Río 2016 (+ una edición extra para la carga 4)

Repetir **exactamente el mismo ciclo** de Pablo, usando estos nombres:

- [ ] Carga inicial (París 2024) + capturas + fragmentación + `full_deporte.bak`
- [ ] Carga 2 (Tokio 2020) + capturas + fragmentación + `diff_deporte_1.bak`
- [ ] Carga 3 (Río 2016) + capturas + fragmentación + `diff_deporte_2.bak`
- [ ] Carga 4 (edición extra) + capturas + fragmentación + `diff_deporte_3.bak`
- [ ] Anotar conteos finales y eliminar la base
- [ ] Restaurar full → tiempo → capturas de validación
- [ ] Restaurar full + diff 1 → tiempo → capturas de validación
- [ ] Restaurar full + diff 2 → tiempo → capturas de validación
- [ ] Restaurar full + diff 3 → tiempo → capturas de validación
- [ ] Guardar scripts y logs en el repositorio
- [ ] Llenar la tabla de tiempos de "Deporte" (sección 5)

> **Ojo:** José debe verificar antes de empezar que los 100 m femeninos de París 2024 existan en los datos. En `olympics_dataset` el evento puede tener otro nombre (por ejemplo "Women's 100m"), distinto al de `resultsFull`.

---

## 3. Gerardo — Carga por DEPORTISTA

**Datos:** Usain Bolt en Atenas 2004 → Pekín 2008 → Londres 2012 (+ una edición extra para la carga 4, por ejemplo Río 2016)

Repetir **exactamente el mismo ciclo** de Pablo, usando estos nombres:

- [ ] Carga inicial (Atenas 2004) + capturas + fragmentación + `full_deportista.bak`
- [ ] Carga 2 (Pekín 2008) + capturas + fragmentación + `diff_deportista_1.bak`
- [ ] Carga 3 (Londres 2012) + capturas + fragmentación + `diff_deportista_2.bak`
- [ ] Carga 4 (edición extra) + capturas + fragmentación + `diff_deportista_3.bak`
- [ ] Anotar conteos finales y eliminar la base
- [ ] Restaurar full → tiempo → capturas de validación
- [ ] Restaurar full + diff 1 → tiempo → capturas de validación
- [ ] Restaurar full + diff 2 → tiempo → capturas de validación
- [ ] Restaurar full + diff 3 → tiempo → capturas de validación
- [ ] Guardar scripts y logs en el repositorio
- [ ] Llenar la tabla de tiempos de "Deportista" (sección 5)

> **Ojo:** con una carga tan chica (un atleta) los tiempos de restauración serán muy cortos y casi iguales entre full y diferencial. Es normal, pero hay que explicarlo en el análisis.

---

## 4. Entregables (repartir como responsabilidad secundaria)

| Entregable | Puntos | Responsable sugerido | Checklist |
|---|---|---|---|
| Manual de Usuario | 10 | Pablo | Pasos de backup y restore con comandos reales · ejemplos de ejecución · cómo interpretar los logs · cómo validar integridad post-restauración |
| Documentación Técnica | 15 | José | Descripción de la metodología · modelo entidad-relación · plan de respaldo · especificaciones técnicas del servidor · gráficos comparativos · conclusiones justificadas |
| Código fuente organizado | 15 | Gerardo | Carpetas `/ddl`, `/carga`, `/backup`, `/restauracion` · scripts comentados · nombres descriptivos · logs de ejecución comentados |
| Análisis comparativo final | (dentro de los 60 pts de conocimientos) | Gerardo | Tabla global de las 3 cargas · gráficos · recomendación sobre qué backup conviene según el volumen de datos |

---

## 5. Plantilla de tiempos de restauración

Cada persona llena su tabla con los segundos medidos por consola.

| Tipo de carga | Restauración | Tiempo (s) | Filas restauradas | Tamaño del .bak |
|---|---|---|---|---|
| Año | Full | 0.965 | 14735 | 119.10 MB |
| Año | Full + Diff 1 | 1.582 | 13951 | 35.10 MB |
| Año | Full + Diff 2 | 1.681 | 13742 | 51.10 MB |
| Año | Full + Diff 3 | 1.555 | 12975 | 68.10 MB |
| Deporte | Full | 0.870 | 3 176 | 37.13 MB |
| Deporte | Full + Diff 1 | 1.415 | 3 992 | 37.13 MB + 4.13 MB |
| Deporte | Full + Diff 2 | 1.302 | 5 207 | 37.13 MB + 4.13 MB |
| Deporte | Full + Diff 3 | 1.338 | 6 285 | 37.13 MB + 5.13 MB |
| Deportista | Full | | | |
| Deportista | Full + Diff 1 | | | |
| Deportista | Full + Diff 2 | | | |
| Deportista | Full + Diff 3 | | | |

---

## 6. Referencia rápida de comandos

```sql
-- Full
BACKUP DATABASE db_olimpiadas
  TO DISK = '/var/opt/mssql/backups/full_anio.bak' WITH INIT, STATS = 10;

-- Diferencial
BACKUP DATABASE db_olimpiadas
  TO DISK = '/var/opt/mssql/backups/diff_anio_1.bak' WITH DIFFERENTIAL, STATS = 10;

-- Restaurar solo el full
RESTORE DATABASE db_olimpiadas
  FROM DISK = '/var/opt/mssql/backups/full_anio.bak' WITH RECOVERY, REPLACE;

-- Restaurar full + diferencial (el full va con NORECOVERY)
RESTORE DATABASE db_olimpiadas
  FROM DISK = '/var/opt/mssql/backups/full_anio.bak' WITH NORECOVERY, REPLACE;
RESTORE DATABASE db_olimpiadas
  FROM DISK = '/var/opt/mssql/backups/diff_anio_1.bak' WITH RECOVERY;
```

```powershell
# Medir el tiempo de una restauración
$inicio = Get-Date
Invoke-Sqlcmd -ServerInstance "localhost" -InputFile "restore_full_diff1.sql"
$fin = Get-Date
"Tiempo: $(($fin - $inicio).TotalSeconds) s"
```

> **Importante:** el diferencial de SQL Server es **acumulativo** (contiene todo lo cambiado desde el último full). Por eso, para restaurar el diferencial N basta con el full + ese diferencial, no hace falta aplicar los anteriores. Esto es justo lo que hay que explicar en el análisis comparativo.

---

## 7. Antes de subir a UEDI

- [ ] Todas las capturas tienen fecha y hora del sistema visibles
- [ ] Los conteos después de restaurar coinciden con los de antes de borrar
- [ ] Los 3 tipos de carga tienen su full, sus 3 diferenciales y sus tiempos
- [ ] La documentación técnica incluye gráficos comparativos y conclusión
- [ ] El manual de usuario tiene comandos reales y cómo interpretar los logs
- [ ] El repositorio está ordenado y los scripts corren
- [ ] Revisión cruzada: cada quien revisa las capturas de los otros dos
- [ ] **Los 3 integrantes subieron en UEDI**

### Opcional (si sobra tiempo)
- [ ] Compresión del backup (`WITH COMPRESSION`)
- [ ] Backups automáticos con script `cron`
- [ ] Cifrado del backup
- [ ] Alertas de validación de integridad tras la restauración (`RESTORE VERIFYONLY`)
