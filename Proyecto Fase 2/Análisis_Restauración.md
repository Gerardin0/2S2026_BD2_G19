# Análisis comparativo de tiempos de restauración

## 1. Objetivo y alcance

Este documento compara los tiempos observados al restaurar los respaldos de
las tres cargas del proyecto: **por año**, **por deporte** y **por deportista**.
Se evalúan cuatro puntos de recuperación para cada base:

1. Solo el respaldo completo (**Full**).
2. El Full más el Diferencial 1.
3. El Full más el Diferencial 2.
4. El Full más el Diferencial 3.

El propósito es describir qué muestran las mediciones de esta corrida, explicar
las diferencias y recomendar una estrategia de respaldo adecuada para este
proyecto. Los resultados son observaciones de una corrida y no una garantía de
rendimiento para otros servidores.

## 2. Fuente y método de medición

Los datos de pared se tomaron de los CSV generados por los medidores:

- `docs/anio/tiempos_restore_anio.csv`
- `docs/deporte/tiempos_restore_deporte.csv`
- `docs/deportista/tiempos_restore_deportista.csv`

La medición comienza **después de eliminar la base** y cronometra la ejecución
del script SQL de restauración. Ese script puede incluir, además de los
comandos `RESTORE`, consultas de validación y presentación de resultados. Por
ello, el valor del CSV es el tiempo de pared del paso de restauración completo,
no exclusivamente el tiempo empleado por el motor en leer y aplicar el backup.
La eliminación de la base no se incluye.

Los logs de SQL Server también registran mensajes como:

```text
RESTORE DATABASE successfully processed N pages in X seconds (Y MB/sec).
```

Esos tiempos `X` reflejan la ejecución de cada comando `RESTORE` en el motor.
Para un escenario Full + Diferencial se suman el tiempo del `RESTORE` Full y
el del `RESTORE` diferencial. La suma permite una comparación más cercana al
trabajo de restauración del motor; no incluye las consultas de validación.

Las mediciones corresponden a la corrida cuyos CSV se generaron el
**16/10/2026**. Los tiempos del motor se tomaron de los logs asociados; las
marcas de tiempo que imprime SQL Server pueden aparecer en UTC, mientras que
los CSV usan hora local.

## 3. Volumen restaurado y tamaño de los respaldos

Los conteos de participación ayudan a interpretar las mediciones: cada
diferencial recupera un estado con más filas que el anterior. En esta carga de
deportista, el contador es específicamente el total de filas de
`participacion JOIN edicion_juego`.

| Flujo | Filas con Full | Filas con Diff 1 | Filas con Diff 2 | Filas con Diff 3 |
|---|---:|---:|---:|---:|
| Año | 14 735 | 28 686 | 42 428 | 55 403 |
| Deporte | 91 | 159 | 239 | 318 |
| Deportista | 1 | 4 | 7 | 10 |

Tamaños aproximados de los archivos presentes en el volumen al hacer el
análisis:

| Flujo | Full | Diff 1 | Diff 2 | Diff 3 | Full + Diff 3 |
|---|---:|---:|---:|---:|---:|
| Año | 120 MB | 36 MB | 52 MB | 69 MB | 189 MB |
| Deporte | 35 MB | 4,2 MB | 4,2 MB | 4,2 MB | 39,2 MB |
| Deportista | 8,2 MB | 4,2 MB | 4,2 MB | 4,2 MB | 12,4 MB |

Las cifras se redondean a partir del tamaño mostrado por `ls -lh`. La columna
Full + Diff 3 suma el Full al diferencial más reciente; **no** suma los tres
diferenciales. Si se conservan los cuatro puntos de recuperación, sí deben
retenerse todos los diferenciales: el espacio total aproximado de los cuatro
archivos es 277 MB para Año, 47,6 MB para Deporte y 20,8 MB para Deportista.

SQL Server crea diferenciales **acumulativos**: cada archivo contiene los
cambios desde el mismo Full, no solo los cambios desde el diferencial
inmediatamente anterior. Por eso, para recuperar el estado Diff 3 se aplican
el Full y Diff 3; Diff 1 y Diff 2 son puntos históricos alternativos, no pasos
de esa misma restauración.

## 4. Comparación de los tiempos

### 4.1 Tiempo de pared del paso de restauración

Valores tomados directamente de los CSV. En el CSV de deporte y deportista,
la configuración regional de PowerShell usa coma decimal.

| Flujo | Solo Full | Full + Diff 1 | Full + Diff 2 | Full + Diff 3 | Más rápido |
|---|---:|---:|---:|---:|---|
| Año | 1,292 s | 1,489 s | 6,872 s | 7,527 s | Solo Full |
| Deporte | 4,941 s | 2,295 s | 1,483 s | 1,679 s | Full + Diff 2 |
| Deportista | 1,002 s | 1,502 s | 2,659 s | 5,344 s | Solo Full |

### 4.2 Tiempo de los comandos RESTORE en el motor

Esta tabla suma las líneas `RESTORE DATABASE successfully processed` de los
logs. Para los escenarios diferenciales incluye tanto el Full como el
diferencial.

| Flujo | Solo Full | Full + Diff 1 | Full + Diff 2 | Full + Diff 3 |
|---|---:|---:|---:|---:|
| Año | 0,507 s | 0,862 s | 5,709 s | 5,917 s |
| Deporte | 3,830 s | 1,483 s | 0,940 s | 0,950 s |
| Deportista | 0,281 s | 0,859 s | 1,773 s | 4,041 s |

Los tiempos de pared y los tiempos del motor no son idénticos porque miden
cosas distintas. Por ejemplo, el tiempo de pared también puede incluir el
inicio de `sqlcmd`, la salida del script y las consultas de verificación.

### 4.3 Cambio frente a restaurar solo el Full

La siguiente tabla expresa cuánto cambia el tiempo de pared de cada estado
Full + Diff respecto al tiempo de pared del Full del mismo flujo.

| Flujo | Full + Diff 1 | Full + Diff 2 | Full + Diff 3 |
|---|---:|---:|---:|
| Año | +15,2 % | +431,9 % | +482,6 % |
| Deporte | −53,6 % | −70,0 % | −66,0 % |
| Deportista | +49,9 % | +165,4 % | +433,1 % |

El signo negativo indica que el escenario Full + Diff fue más rápido en esa
medición puntual que el escenario solo Full. No significa que aplicar un
diferencial sea siempre más rápido; la lectura secuencial y el estado de la
caché y del almacenamiento afectan el tiempo.

## 5. Análisis por flujo

### 5.1 Carga por año

- El Full restauró 14 735 participaciones; Diff 3 restauró 55 403.
- El Full ocupaba aproximadamente 120 MB y Diff 3, 69 MB. Para el último
  estado se requieren ambos archivos, cerca de 189 MB en conjunto.
- El tiempo del motor pasó de 0,507 s para el Full a 5,917 s para Full + Diff 3.
  El tiempo de pared pasó de 1,292 s a 7,527 s.
- En los logs, el Full procesó 15 122 páginas; Diff 3 procesó 8 586 páginas
  adicionales. Los diferenciales mayores requieren más trabajo que Diff 1.

En esta corrida, restaurar solo el Full fue claramente más rápido. El costo de
Full + Diff 2 y Full + Diff 3 es coherente con los mayores volúmenes de datos y
con el tamaño acumulado de esos diferenciales.

### 5.2 Carga por deporte

- El Full restauró 91 participaciones y Diff 3, 318.
- El Full ocupaba aproximadamente 35 MB; cada diferencial se observa en torno
  a 4,2 MB.
- El CSV muestra 4,941 s para Full, frente a 1,483 s para Full + Diff 2. Sin
  embargo, el log del motor también muestra que solo el Full tardó 3,830 s,
  mientras que el Full + Diff 2 tardó en conjunto 0,940 s.
- Esta diferencia entre escenarios demuestra que las mediciones son sensibles
  a la variabilidad del almacenamiento o de la carga del entorno. No es
  evidencia de que una restauración diferencial siempre supere al Full.

El diferencial permitió recuperar más ediciones con un tiempo menor en esta
corrida, pero el Full aislado fue un dato atípicamente lento. Sin mediciones
repetidas no se debe atribuir esa diferencia únicamente al tipo de respaldo.

### 5.3 Carga por deportista

- El Full restauró 1 participación; Diff 3 restauró 10.
- El Full ocupaba aproximadamente 8,2 MB y cada diferencial se observa en
  torno a 4,2 MB. Para recuperar Diff 3 se necesitan aproximadamente 12,4 MB.
- El tiempo de pared creció de 1,002 s para Full a 5,344 s para Full + Diff 3;
  el tiempo del motor creció de 0,281 s a 4,041 s.
- Aunque solo se añadieron pocas filas, el diferencial tiene un tamaño
  relativamente grande frente al Full. El tamaño de un `.bak` depende de las
  páginas cambiadas y de la estructura asignada en la base, no solo del número
  de filas de negocio.

En este conjunto pequeño, el Full resulta la opción más rápida para el punto
inicial, pero las restauraciones Full + Diff 2 y Full + Diff 3 tardan más. Los
diferenciales siguen siendo útiles para preservar los puntos históricos de las
cargas sucesivas; su ventaja de tiempo no se demuestra en esta muestra.

## 6. Lectura conjunta y límites de la comparación

1. **Los tamaños de las tres bases son distintos.** Año tiene decenas de miles
   de participaciones, Deporte cientos y Deportista diez como máximo. Comparar,
   por ejemplo, 1,679 s de Deporte con 5,344 s de Deportista como si fueran
   alternativas sobre el mismo volumen sería incorrecto.
2. **Los diferenciales son acumulativos.** Un Diff 3 mayor contiene los cambios
   desde el Full y es normal que requiera más trabajo que Diff 1. La tendencia
   creciente es visible con claridad en Año y Deportista.
3. **La duración no depende solo del tipo de backup.** El dispositivo físico,
   Docker, el volumen compartido, la caché, el crecimiento de archivos, otras
   tareas del host, el arranque de `sqlcmd` y las consultas de validación
   pueden afectar los resultados.
4. **Una sola medición no permite separar bien esos efectos.** Deporte muestra
   la variación más evidente: el Full es el escenario más lento pese a procesar
   menos datos que Full + Diff 1. Se necesitarían varias corridas con el mismo
   estado del host, y comparar medianas, para afirmar una ventaja estable.
5. **Las restauraciones no son intercambiables.** Solo Full recupera el estado
   inicial. Full + Diff N recupera el estado después de la carga N+1 y exige
   que el diferencial corresponda exactamente a ese Full.
6. **Un diferencial requiere dos pasos de restore.** Se debe aplicar el Full
   con `NORECOVERY` y el diferencial con `RECOVERY`; un Full restaurado con
   `RECOVERY` ya no acepta la aplicación posterior del diferencial.

## 7. Recomendación

Para el objetivo de este proyecto la opción más apropiada es **Full periódico más
diferenciales**, conservando el Full y los diferenciales que representen los
puntos de recuperación que se quieran retener.

La recomendación se fundamenta en que:

- Un Full autónomo solo ofrece el punto posterior a la primera carga; no
  recupera las cargas posteriores.
- Cada diferencial da un punto de restauración adicional sin exigir aplicar
  los diferenciales previos: basta el Full correcto y el diferencial elegido.
- Los archivos diferenciales son menores que el Full en Año y Deporte, y el
  último diferencial permite recuperar el estado más reciente usando solo dos
  archivos.
- Los tiempos observados muestran el costo de restaurar cambios acumulados,
  sobre todo en Año y Deportista. Por tanto, conviene establecer una política
  de Full nuevo periódicamente —o cuando los diferenciales acumulados crezcan
  demasiado— para acotar el tiempo y la cantidad de páginas que hay que
  recuperar.

**Si la prioridad absoluta fuera el menor tiempo para volver al punto inicial**,
el Full aislado fue más rápido en las mediciones de Año y Deportista. Pero ese
no es un sustituto de la estrategia completa: no preserva los estados
posteriores. En Deporte, el Full aislado tardó más en esta corrida y confirma
que estos datos no permiten afirmar un ganador universal basándose solo en
tiempo.

En síntesis: usar **Full + diferenciales para la recuperación operativa con
múltiples puntos**, renovar el Full para evitar una cadena de cambios
acumulados demasiado grande, y conservar Full únicamente cuando baste el punto
inicial o se priorice simplicidad sobre el historial.

### Evidencias consultadas

- CSV: `docs/anio/tiempos_restore_anio.csv`,
  `docs/deporte/tiempos_restore_deporte.csv` y
  `docs/deportista/tiempos_restore_deportista.csv`.
- Logs: `logs/02_restore_solo_full_anio.log`,
  `logs/03_restore_full_diff1_anio.log`,
  `logs/04_restore_full_diff2_anio.log`,
  `logs/05_restore_full_diff3_anio.log`,
  `logs/restore_deporte_Full*.log` y `logs/restore_Full*.log`.
- Tamaños observados en los archivos `.bak` del volumen local `backups/`.
- Scripts de medición: `docs/anio/medir_tiempos_restore.sh`,
  `docs/deporte/medir_tiempos_restore.ps1` y
  `docs/deportista/medir_tiempos_restore.ps1`.
