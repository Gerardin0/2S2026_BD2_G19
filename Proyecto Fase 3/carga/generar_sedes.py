#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
from pathlib import Path

def main():
    raiz_repo = Path(__file__).resolve().parents[2]
    ruta_in = raiz_repo / "Proyecto Fase 1" / "worked_datasets" / "tabla_edicion_juego.csv"
    ruta_out = Path(__file__).resolve().parents[1] / "fuentes" / "ediciones_sede.csv"

    ruta_out.parent.mkdir(parents=True, exist_ok=True)

    # Diccionario maestro unificado (id_edicion: [ciudad, noc_sede, categoria])
    correcciones = {
        "1": ["Athina", "GRE", "Special"], "2": ["Athina", "GRE", "Olympics"],
        "3": ["Paris", "FRA", "Olympics"], "4": ["St. Louis", "USA", "Olympics"],
        "5": ["Athina", "GRE", "Special"], "6": ["London", "GBR", "Olympics"],
        "7": ["Stockholm", "SWE", "Olympics"], "8": ["Antwerpen", "BEL", "Olympics"],
        "9": ["Paris", "FRA", "Olympics"], "10": ["Chamonix", "FRA", "Olympics"],
        "11": ["Amsterdam", "NED", "Olympics"], "12": ["Sankt Moritz", "SUI", "Olympics"],
        "13": ["Los Angeles", "USA", "Olympics"], "14": ["Lake Placid", "USA", "Olympics"],
        "15": ["Berlin", "GER", "Olympics"], "16": ["Garmisch-Partenkirchen", "GER", "Olympics"],
        "17": ["London", "GBR", "Olympics"], "18": ["Sankt Moritz", "SUI", "Olympics"],
        "19": ["Helsinki", "FIN", "Olympics"], "20": ["Oslo", "NOR", "Olympics"],
        "21": ["Stockholm", "SWE", "Special"], "22": ["Melbourne", "AUS", "Olympics"],
        "23": ["Cortina d'Ampezzo", "ITA", "Olympics"], "24": ["Roma", "ITA", "Olympics"],
        "25": ["Squaw Valley", "USA", "Olympics"], "26": ["Tokyo", "JPN", "Olympics"],
        "27": ["Innsbruck", "AUT", "Olympics"], "28": ["Ciudad de Mexico", "MEX", "Olympics"],
        "29": ["Grenoble", "FRA", "Olympics"], "30": ["Munich", "FRG", "Olympics"],
        "31": ["Sapporo", "JPN", "Olympics"], "32": ["Montreal", "CAN", "Olympics"],
        "33": ["Innsbruck", "AUT", "Olympics"], "34": ["Moskva", "URS", "Olympics"],
        "35": ["Lake Placid", "USA", "Olympics"], "36": ["Los Angeles", "USA", "Olympics"],
        "37": ["Sarajevo", "YUG", "Olympics"], "38": ["Seoul", "KOR", "Olympics"],
        "39": ["Calgary", "CAN", "Olympics"], "40": ["Barcelona", "ESP", "Olympics"],
        "41": ["Albertville", "FRA", "Olympics"], "42": ["Lillehammer", "NOR", "Olympics"],
        "43": ["Atlanta", "USA", "Olympics"], "44": ["Nagano", "JPN", "Olympics"],
        "45": ["Sydney", "AUS", "Olympics"], "46": ["Salt Lake City", "USA", "Olympics"],
        "47": ["Athina", "GRE", "Olympics"], "48": ["Torino", "ITA", "Olympics"],
        "49": ["Beijing", "CHN", "Olympics"], "50": ["Singapore", "SGP", "Youth"],
        "51": ["Vancouver", "CAN", "Olympics"], "52": ["London", "GBR", "Olympics"],
        "53": ["Innsbruck", "AUT", "Youth"], "54": ["Nanjing", "CHN", "Youth"],
        "55": ["Sochi", "RUS", "Olympics"], "56": ["Rio de Janeiro", "BRA", "Olympics"],
        "57": ["Lillehammer", "NOR", "Youth"], "58": ["Buenos Aires", "ARG", "Youth"],
        "59": ["PyeongChang", "KOR", "Olympics"], "60": ["Tokyo", "JPN", "Olympics"],
        "61": ["Lausanne", "SUI", "Youth"], "62": ["Beijing", "CHN", "Olympics"],
        "63": ["Paris", "FRA", "Olympics"]
    }

    with open(ruta_in, mode='r', encoding='utf-8') as f_in, \
         open(ruta_out, mode='w', encoding='utf-8', newline='') as f_out:
        
        lector = csv.reader(f_in)
        escritor = csv.writer(f_out)
        
        next(lector, None) # Saltar cabecera de origen
        escritor.writerow(["id_edicion_juego", "anio", "temporada", "ciudad", "noc_sede", "categoria"])
        
        filas = 0
        for fila in lector:
            if len(fila) >= 4:
                id_edicion = fila[0].strip()
                anio = fila[1].strip().replace(".0", "")
                temporada = fila[2].strip()
                
                # Buscamos los datos limpios en el diccionario
                if id_edicion in correcciones:
                    ciudad, noc_sede, categoria = correcciones[id_edicion]
                else:
                    ciudad = fila[3].strip()
                    noc_sede = ""
                    categoria = "Olympics"
                
                escritor.writerow([id_edicion, anio, temporada, ciudad, noc_sede, categoria])
                filas += 1

    print(f"Archivo unificado generado con éxito: {filas} ediciones procesadas en {ruta_out.name}")

if __name__ == "__main__":
    main()