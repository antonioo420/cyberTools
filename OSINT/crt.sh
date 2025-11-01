#!/bin/bash

# Script para consultar subdominios en crt.sh

# Verificar que se proporcione un dominio
if [ $# -eq 0 ]; then
    echo "Uso: $0 <dominio>"
    echo "Ejemplo: $0 example.com"
    exit 1
fi

dominio="$1"
# Extraer solo el nombre base del dominio (sin extensión)
nombre_base=$(echo "$dominio" | cut -d'.' -f1)
archivo_salida="${nombre_base}.txt"

echo "[+] Consultando crt.sh para el dominio: $dominio"
echo "[+] Esto puede tardar unos segundos..."

# Hacer curl a crt.sh y procesar el HTML
curl -s "https://crt.sh/?q=%25.$dominio" | \
    grep -oP '(?<=<TD>)[^<]+(?=</TD>)' | \
    grep -E "^[a-zA-Z0-9*._-]+\.$dominio$" | \
    sed 's/\*\.//g' | \
    sort -u > "$archivo_salida"

# Verificar si se obtuvieron resultados
if [ -s "$archivo_salida" ]; then
    num_subdominios=$(wc -l < "$archivo_salida")
    echo "[+] Se encontraron $num_subdominios subdominios únicos"
    echo "[+] Resultados guardados en: $archivo_salida"
else
    echo "[-] No se encontraron subdominios para $dominio"
    rm -f "$archivo_salida"
    exit 1
fi
