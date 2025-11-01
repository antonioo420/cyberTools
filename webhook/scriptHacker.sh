#!/bin/bash


# Script para interactuar con Claude desde la terminal

# Requiere: curl, jq

# Uso: ./claude-chat.sh "tu pregunta aquí"


# Colores para la salida

GREEN='\033[0;32m'

BLUE='\033[0;34m'

RED='\033[0;31m'

NC='\033[0m' # Sin color


# Configuración

API_KEY="${ANTHROPIC_API_KEY}"

MODEL="claude-sonnet-4-5-20250929"

API_URL="https://api.anthropic.com/v1/messages"

MAX_TOKENS=4096


# Archivo para guardar el historial de conversación

HISTORY_FILE="${HOME}/.claude_history.json"


# Función para mostrar uso

show_usage() {

    echo "Uso: $0 [opciones] \"mensaje\""

    echo ""

    echo "Opciones:"

    echo "  -h, --help          Muestra esta ayuda"

    echo "  -n, --new           Inicia una nueva conversación"

    echo "  -m, --model MODEL   Especifica el modelo (default: claude-sonnet-4-5-20250929)"

    echo "  -t, --tokens NUM    Número máximo de tokens (default: 4096)"

    echo "  -i, --interactive   Modo interactivo"

    echo ""

    echo "Configuración:"

    echo "  Define ANTHROPIC_API_KEY en tu entorno o en ~/.bashrc"

    echo "  export ANTHROPIC_API_KEY='tu-api-key'"

}


# Verificar dependencias

check_dependencies() {

    if ! command -v curl &> /dev/null; then

        echo -e "${RED}Error: curl no está instalado${NC}"

        exit 1

    fi

    

    if ! command -v jq &> /dev/null; then

        echo -e "${RED}Error: jq no está instalado${NC}"

        echo "Instálalo con: sudo apt install jq (Ubuntu/Debian) o brew install jq (macOS)"

        exit 1

    fi

}


# Verificar API key

check_api_key() {

    if [ -z "$API_KEY" ]; then

        echo -e "${RED}Error: ANTHROPIC_API_KEY no está configurada${NC}"

        echo "Configúrala con: export ANTHROPIC_API_KEY='tu-api-key'"

        exit 1

    fi

}


# Inicializar historial

init_history() {

    if [ ! -f "$HISTORY_FILE" ] || [ "$NEW_CHAT" = true ]; then

        echo "[]" > "$HISTORY_FILE"

    fi

}


# Leer historial

read_history() {

    if [ -f "$HISTORY_FILE" ]; then

        cat "$HISTORY_FILE"

    else

        echo "[]"

    fi

}


# Guardar mensaje en historial

save_to_history() {

    local role=$1

    local content=$2

    local history=$(read_history)

    

    local new_message=$(jq -n \

        --arg role "$role" \

        --arg content "$content" \

        '{role: $role, content: $content}')

    

    echo "$history" | jq --argjson msg "$new_message" '. += [$msg]' > "$HISTORY_FILE"

}


# Enviar mensaje a Claude

send_message() {

    local user_message=$1

    local history=$(read_history)

    

    # Añadir mensaje del usuario al historial

    save_to_history "user" "$user_message"

    history=$(read_history)

    

    # Preparar la petición

    local request_body=$(jq -n \

        --arg model "$MODEL" \

        --argjson max_tokens "$MAX_TOKENS" \

        --argjson messages "$history" \

        '{

            model: $model,

            max_tokens: $max_tokens,

            messages: $messages

        }')

    

    # Hacer la petición a la API

    echo -e "${BLUE}Claude:${NC}"

    local response=$(curl -s "$API_URL" \

        -H "Content-Type: application/json" \

        -H "x-api-key: $API_KEY" \

        -H "anthropic-version: 2023-06-01" \

        -d "$request_body")

    

    # Verificar errores

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then

        echo -e "${RED}Error:${NC} $(echo "$response" | jq -r '.error.message')"

        return 1

    fi

    

    # Extraer y mostrar la respuesta

    local assistant_message=$(echo "$response" | jq -r '.content[0].text')

    echo "$assistant_message"

    echo ""

    

    # Guardar respuesta en historial

    save_to_history "assistant" "$assistant_message"

}


# Modo interactivo

interactive_mode() {

    echo -e "${GREEN}=== Modo Interactivo de Claude ===${NC}"

    echo "Escribe 'salir' o 'exit' para terminar"

    echo "Escribe 'nuevo' o 'new' para iniciar una nueva conversación"

    echo ""

    

    while true; do

        echo -ne "${GREEN}Tú:${NC} "

        read -r user_input

        

        if [ -z "$user_input" ]; then

            continue

        fi

        

        case "$user_input" in

            salir|exit|quit)

                echo "¡Hasta luego!"

                exit 0

                ;;

            nuevo|new)

                echo "[]" > "$HISTORY_FILE"

                echo -e "${BLUE}Nueva conversación iniciada${NC}"

                echo ""

                continue

                ;;

        esac

        

        send_message "$user_input"

    done

}


# Procesar argumentos

NEW_CHAT=false

INTERACTIVE=false


while [[ $# -gt 0 ]]; do

    case $1 in

        -h|--help)

            show_usage

            exit 0

            ;;

        -n|--new)

            NEW_CHAT=true

            shift

            ;;

        -m|--model)

            MODEL="$2"

            shift 2

            ;;

        -t|--tokens)

            MAX_TOKENS="$2"

            shift 2

            ;;

        -i|--interactive)

            INTERACTIVE=true

            shift

            ;;

        *)

            MESSAGE="$1"

            shift

            ;;

    esac

done


# Verificar dependencias y API key

check_dependencies

check_api_key

init_history


# Ejecutar en modo interactivo o con mensaje único

if [ "$INTERACTIVE" = true ]; then

    interactive_mode

elif [ -n "$MESSAGE" ]; then

    send_message "$MESSAGE"

else

    show_usage

    exit 1

fi
