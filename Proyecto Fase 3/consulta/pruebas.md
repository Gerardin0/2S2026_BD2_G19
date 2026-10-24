# Casos de prueba de las consultas (C4)

Los casos se ejecutan y verifican automáticamente con:

```bash
python consulta/ejecutar_pruebas.py          # todos
python consulta/ejecutar_pruebas.py P05 P14  # algunos
```

El script corre cada comando, revisa que la salida contenga el texto esperado y guarda la salida
completa, con fecha y hora, en `docs/logs/pruebas_consultas_<fecha>.log`.

**Última ejecución:** 2026-10-20 21:45 (22/22 OK). La bitácora es `docs/logs/pruebas_consultas_20261020_214548.log`.

## Consulta por atleta (`atleta.py`)

| ID | Caso | Comando | Salida esperada |
| --- | --- | --- | --- |
| P01 | Nombre exacto con tildes | `python consulta/atleta.py "Érick Barrondo"` | Ficha id 123159, GUA, plata en *20 kilometres Race Walk* (Londres 2012, pos. 2) |
| P02 | Sin tildes, palabras en otro orden | `python consulta/atleta.py "barrondo erick"` | La misma ficha que P01 |
| P03 | Nombre parcial | `python consulta/atleta.py phelp --max-atletas 1` | Lista de coincidencias. Primero Michael Phelps (Oro 23, Plata 3, Bronce 2) |
| P04 | Atleta inexistente | `python consulta/atleta.py "Zzyzx Qwerty"` | `No se encontró ningún atleta para "Zzyzx Qwerty".` |
| P05 | Nombre repetido | `python consulta/atleta.py "John Smith" --max-atletas 1` | Tabla de 12 coincidencias. Las 4 exactas van marcadas `← exacto` y se ordenan por medallas. Se muestra la ficha de la primera (id 60764) |
| P06 | Filtros año + medalla | `python consulta/atleta.py "Michael Phelps" --anio 2008 --medalla oro` | `Participaciones : 8 de 30` y `Medallas (filtro): Oro 8` |
| P07 | Filtro sin coincidencias | `python consulta/atleta.py "Michael Phelps" --anio 1990` | `No se encontró ningún atleta … con filtros (anio=1990)` |
| P08 | Edición especial 1906 | `python consulta/atleta.py "Archie Hahn" --anio 1906` | `1906 Intercalated Games (Athina, Special)`, oro en *100 metres, Men (Intercalated)* |
| P09 | Juegos de la Juventud | `python consulta/atleta.py "Alejandra Orozco"` | La línea de ediciones incluye `2014 Summer (Nanjing, Youth)` |
| P10 | Corrección C3 (2024) | `python consulta/atleta.py "Pierre Brol"` | GUA. Bronce en *Trap, Men* París 2024 |
| P11 | Corrección C3 (2024) | `python consulta/atleta.py "Shayna Jack"` | AUS, solo natación. Ya **no** aparece el *Trap, Men* que antes tenía asignado por error |

## Consulta por país (`pais.py`)

| ID | Caso | Comando | Salida esperada |
| --- | --- | --- | --- |
| P12 | Por código NOC | `python consulta/pais.py GUA` | `¿Ha sido sede? NO`. Medallero Oro 1, Plata 1, Bronce 1. 18 años de participación. Lista de medallas (Ruano, Brol, Barrondo) |
| P13 | Por nombre | `python consulta/pais.py guatemala` | La misma salida que P12 |
| P14 | País inexistente | `python consulta/pais.py XYZ` | `No existe ningún país con código o nombre "XYZ".` |
| P15 | País sin población | `python consulta/pais.py URS` | `Población: sin datos`. Fue sede una vez (Moskva 1980) |
| P16 | Sede varias veces | `python consulta/pais.py USA` | `SÍ, 8 veces` (de St. Louis 1904 a Salt Lake City 2002). En la tabla por edición las ediciones sede van marcadas `SEDE` |
| P17 | Nombre ambiguo | `python consulta/pais.py Germany` | `4 países coinciden` (GER, FRG, GDR, SAA) y se despliegan todos |
| P18 | Código unificado | `python consulta/pais.py ROC --anio 2020` | `Nota: ROC se cargó unificado con RUS`. Russia, Tokio 2020 |
| P19 | País en Juegos de la Juventud | `python consulta/pais.py GUA --anio 2010` | Singapore, categoría Youth |
| P20 | País en 1906 | `python consulta/pais.py GRE --anio 1906` | Edición *Intercalated Games* en Athina, marcada `SEDE` |
| P21 | Resultados + atletas | `python consulta/pais.py GUA --anio 2024 --atletas --resultados` | `Atletas (16)` y `Participaciones y resultados (16)`, con posición |
| P22 | Rango + deporte | `python consulta/pais.py MEX --desde 2000 --hasta 2020 --deporte Diving` | `Medallero con filtros` y medallas solo de *Diving (Aquatics)* |

## Limitaciones conocidas de los datos (no son errores de la consulta)

- **Juegos de la Juventud incompletos en la fuente.** La Fase 1 solo trae parte de los YOG. Por ejemplo,
  Buenos Aires 2018 tiene 47 participaciones. Por eso `atleta.py garcia --anio 2018 --temporada summer` no
  devuelve nada.
- **Sin población:** 46 NOC no tienen datos del Banco Mundial. Son países históricos (URS, GDR, YUG, TCH…)
  o códigos sin mapeo ISO-3 en `fuentes/iso3_noc.csv` (PUR, TPE, KUW, LAT, VIE, SGP, LBN, ALG…).
- **Duplicados de la Fase 1:** algunos atletas de 2024 quedaron como persona nueva aunque ya existían en `bios.csv`.
  Por ejemplo, *Jean-Pierre Brol* (id 123253, Londres 2012) y *Pierre Brol* (id 155583, París 2024).
- **Medallero por evento:** si un país gana dos medallas iguales en el mismo evento (por ejemplo, dos bronces en
  judo), cuentan como una. El conteo por atleta (`Medallas por atleta`) sí las incluye.
