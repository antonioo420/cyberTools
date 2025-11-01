#!/bin/bash

# Script de auditoría de seguridad del sistema
# Recopila información de seguridad y la envía a un webhook

# Configuración
WEBHOOK_URL="https://nmizknpbkovfusurmxxq.supabase.co/functions/v1/envio"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")
OUTPUT_FILE="auditoria_seguridad_$(date +%Y%m%d_%H%M%S).json"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "============================================================"
echo "           AUDITORÍA DE SEGURIDAD DEL SISTEMA"
echo "============================================================"
echo ""
echo -e "${BLUE}Analizando configuraciones de seguridad...${NC}"
echo ""

# Función para escapar JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n'
}

# Iniciar JSON
JSON_DATA="{"
JSON_DATA+="\"timestamp\":\"$TIMESTAMP\","
JSON_DATA+="\"hostname\":\"$(hostname)\","

# 1. INFORMACIÓN DEL SISTEMA
echo -e "${YELLOW}[1/10]${NC} Recopilando información del sistema..."
OS_INFO=$(uname -a)
if [ -f /etc/os-release ]; then
    DISTRO=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
else
    DISTRO="N/A"
fi

JSON_DATA+="\"sistema\":{"
JSON_DATA+="\"os\":\"$(escape_json "$OS_INFO")\","
JSON_DATA+="\"distribucion\":\"$DISTRO\","
JSON_DATA+="\"kernel\":\"$(uname -r)\","
JSON_DATA+="\"arquitectura\":\"$(uname -m)\""
JSON_DATA+="},"

# 2. USUARIOS Y GRUPOS
echo -e "${YELLOW}[2/10]${NC} Analizando usuarios y privilegios..."

# Usuarios con shell
USERS_WITH_SHELL=$(grep -E '/bash$|/sh$|/zsh$|/fish$' /etc/passwd 2>/dev/null | cut -d: -f1 | paste -sd "," - || echo "N/A")

# Usuarios con UID 0 (root)
ROOT_USERS=$(awk -F: '$3 == 0 {print $1}' /etc/passwd 2>/dev/null | paste -sd "," - || echo "root")

# Usuarios sin password
USERS_NO_PASS=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | paste -sd "," - || echo "N/A - Requiere privilegios")

# Contar usuarios totales
TOTAL_USERS=$(wc -l < /etc/passwd 2>/dev/null || echo "N/A")

JSON_DATA+="\"usuarios\":{"
JSON_DATA+="\"total\":\"$TOTAL_USERS\","
JSON_DATA+="\"con_shell\":\"$USERS_WITH_SHELL\","
JSON_DATA+="\"usuarios_root\":\"$ROOT_USERS\","
JSON_DATA+="\"sin_password\":\"$USERS_NO_PASS\""
JSON_DATA+="},"

# 3. SESIONES ACTIVAS
echo -e "${YELLOW}[3/10]${NC} Verificando sesiones activas..."

LOGGED_USERS=$(who | wc -l 2>/dev/null || echo "0")
ACTIVE_SESSIONS=$(w -h 2>/dev/null | awk '{print $1" - "$3}' | paste -sd "; " - || echo "N/A")

JSON_DATA+="\"sesiones\":{"
JSON_DATA+="\"usuarios_conectados\":\"$LOGGED_USERS\","
JSON_DATA+="\"sesiones_activas\":\"$(escape_json "$ACTIVE_SESSIONS")\""
JSON_DATA+="},"

# 4. FIREWALL Y RED
echo -e "${YELLOW}[4/10]${NC} Verificando configuración de firewall..."

# Estado del firewall
if command -v ufw &> /dev/null; then
    FIREWALL_STATUS=$(ufw status 2>/dev/null | head -1 || echo "N/A")
    FIREWALL_TYPE="UFW"
elif command -v firewall-cmd &> /dev/null; then
    FIREWALL_STATUS=$(firewall-cmd --state 2>/dev/null || echo "N/A")
    FIREWALL_TYPE="firewalld"
elif command -v iptables &> /dev/null; then
    IPTABLES_RULES=$(iptables -L -n 2>/dev/null | wc -l || echo "0")
    FIREWALL_STATUS="iptables: $IPTABLES_RULES reglas"
    FIREWALL_TYPE="iptables"
else
    FIREWALL_STATUS="No detectado"
    FIREWALL_TYPE="Ninguno"
fi

# Puertos abiertos
if command -v ss &> /dev/null; then
    OPEN_PORTS=$(ss -tuln 2>/dev/null | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -u | paste -sd "," - || echo "N/A")
elif command -v netstat &> /dev/null; then
    OPEN_PORTS=$(netstat -tuln 2>/dev/null | grep LISTEN | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | paste -sd "," - || echo "N/A")
else
    OPEN_PORTS="N/A - Comando no disponible"
fi

JSON_DATA+="\"firewall\":{"
JSON_DATA+="\"tipo\":\"$FIREWALL_TYPE\","
JSON_DATA+="\"estado\":\"$(escape_json "$FIREWALL_STATUS")\","
JSON_DATA+="\"puertos_escucha\":\"$OPEN_PORTS\""
JSON_DATA+="},"

# 5. SERVICIOS CRÍTICOS
echo -e "${YELLOW}[5/10]${NC} Verificando servicios críticos..."

check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo "activo"
    else
        echo "inactivo"
    fi
}

SSH_STATUS=$(check_service ssh || check_service sshd)
CRON_STATUS=$(check_service cron || check_service crond)
FAIL2BAN_STATUS=$(check_service fail2ban)

JSON_DATA+="\"servicios\":{"
JSON_DATA+="\"ssh\":\"$SSH_STATUS\","
JSON_DATA+="\"cron\":\"$CRON_STATUS\","
JSON_DATA+="\"fail2ban\":\"$FAIL2BAN_STATUS\""
JSON_DATA+="},"

# 6. ACTUALIZACIONES PENDIENTES
echo -e "${YELLOW}[6/10]${NC} Verificando actualizaciones pendientes..."

if command -v apt &> /dev/null; then
    apt update -qq 2>/dev/null
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    UPDATE_TYPE="APT"
elif command -v yum &> /dev/null; then
    UPDATES=$(yum check-update -q 2>/dev/null | grep -v "^$" | wc -l || echo "0")
    UPDATE_TYPE="YUM"
elif command -v dnf &> /dev/null; then
    UPDATES=$(dnf check-update -q 2>/dev/null | grep -v "^$" | wc -l || echo "0")
    UPDATE_TYPE="DNF"
else
    UPDATES="N/A"
    UPDATE_TYPE="Desconocido"
fi

JSON_DATA+="\"actualizaciones\":{"
JSON_DATA+="\"gestor_paquetes\":\"$UPDATE_TYPE\","
JSON_DATA+="\"pendientes\":\"$UPDATES\""
JSON_DATA+="},"

# 7. PERMISOS DE ARCHIVOS CRÍTICOS
echo -e "${YELLOW}[7/10]${NC} Verificando permisos de archivos críticos..."

check_file_perms() {
    if [ -f "$1" ]; then
        stat -c "%a" "$1" 2>/dev/null || stat -f "%p" "$1" 2>/dev/null | tail -c 4
    else
        echo "N/A"
    fi
}

PASSWD_PERMS=$(check_file_perms "/etc/passwd")
SHADOW_PERMS=$(check_file_perms "/etc/shadow")
SUDOERS_PERMS=$(check_file_perms "/etc/sudoers")

JSON_DATA+="\"permisos_archivos\":{"
JSON_DATA+="\"etc_passwd\":\"$PASSWD_PERMS\","
JSON_DATA+="\"etc_shadow\":\"$SHADOW_PERMS\","
JSON_DATA+="\"etc_sudoers\":\"$SUDOERS_PERMS\""
JSON_DATA+="},"

# 8. CONFIGURACIÓN SSH
echo -e "${YELLOW}[8/10]${NC} Analizando configuración SSH..."

if [ -f /etc/ssh/sshd_config ]; then
    ROOT_LOGIN=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "no especificado")
    PASSWORD_AUTH=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "no especificado")
    SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
else
    ROOT_LOGIN="config no encontrada"
    PASSWORD_AUTH="config no encontrada"
    SSH_PORT="N/A"
fi

JSON_DATA+="\"ssh_config\":{"
JSON_DATA+="\"permit_root_login\":\"$ROOT_LOGIN\","
JSON_DATA+="\"password_authentication\":\"$PASSWORD_AUTH\","
JSON_DATA+="\"puerto\":\"$SSH_PORT\""
JSON_DATA+="},"

# 9. LOGS DE SEGURIDAD RECIENTES
echo -e "${YELLOW}[9/10]${NC} Analizando logs de seguridad..."

# Últimos intentos de login fallidos
if [ -f /var/log/auth.log ]; then
    FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 | wc -l || echo "0")
    SUDO_COMMANDS=$(grep "sudo:" /var/log/auth.log 2>/dev/null | tail -5 | wc -l || echo "0")
elif [ -f /var/log/secure ]; then
    FAILED_LOGINS=$(grep "Failed password" /var/log/secure 2>/dev/null | tail -5 | wc -l || echo "0")
    SUDO_COMMANDS=$(grep "sudo:" /var/log/secure 2>/dev/null | tail -5 | wc -l || echo "0")
else
    FAILED_LOGINS="Log no accesible"
    SUDO_COMMANDS="Log no accesible"
fi

JSON_DATA+="\"logs_recientes\":{"
JSON_DATA+="\"intentos_fallidos_ultimos\":\"$FAILED_LOGINS\","
JSON_DATA+="\"comandos_sudo_recientes\":\"$SUDO_COMMANDS\""
JSON_DATA+="},"

# 10. PROCESOS SOSPECHOSOS Y RECURSOS
echo -e "${YELLOW}[10/10]${NC} Verificando procesos activos..."

TOTAL_PROCESSES=$(ps aux 2>/dev/null | wc -l || echo "N/A")
ROOT_PROCESSES=$(ps aux 2>/dev/null | grep "^root" | wc -l || echo "N/A")

# Top 5 procesos por CPU
TOP_CPU=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{print $11}' | paste -sd "," - || echo "N/A")

# Top 5 procesos por memoria
TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{print $11}' | paste -sd "," - || echo "N/A")

JSON_DATA+="\"procesos\":{"
JSON_DATA+="\"total\":\"$TOTAL_PROCESSES\","
JSON_DATA+="\"ejecutados_por_root\":\"$ROOT_PROCESSES\","
JSON_DATA+="\"top_cpu\":\"$TOP_CPU\","
JSON_DATA+="\"top_memoria\":\"$TOP_MEM\""
JSON_DATA+="}"

# Cerrar JSON
JSON_DATA+="}"

# Guardar en archivo
echo "$JSON_DATA" | python3 -m json.tool > "$OUTPUT_FILE" 2>/dev/null || echo "$JSON_DATA" > "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}✓${NC} Auditoría guardada localmente: $OUTPUT_FILE"

# Mostrar resumen
echo ""
echo "--- RESUMEN DE SEGURIDAD ---"
echo -e "Sistema: $DISTRO"
echo -e "Usuarios con shell: $USERS_WITH_SHELL"
echo -e "Usuarios con UID 0: $ROOT_USERS"
echo -e "Sesiones activas: $LOGGED_USERS"
echo -e "Firewall: $FIREWALL_TYPE - $FIREWALL_STATUS"
echo -e "SSH Root Login: $ROOT_LOGIN"
echo -e "Actualizaciones pendientes: $UPDATES"
echo -e "Intentos de login fallidos (recientes): $FAILED_LOGINS"
echo ""

# Enviar al webhook
echo -e "${BLUE}Enviando auditoría al webhook...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_DATA" \
    --max-time 10)

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
    echo -e "${GREEN}✓${NC} Auditoría enviada exitosamente al webhook (HTTP $HTTP_CODE)"
else
    echo -e "${RED}✗${NC} Error al enviar al webhook (HTTP $HTTP_CODE)"
fi

echo ""
echo "============================================================"
echo "              AUDITORÍA COMPLETADA"
echo "============================================================"
