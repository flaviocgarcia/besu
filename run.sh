#!/bin/bash

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "Docker não encontrado. Por favor instale o Docker e tente novamente."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Docker não está executando. Por favor inicie o Docker e tende novamente."
    exit 1
fi

echo "Docker instalado e executando."

#Verifica se setup já foi executado
if [ ! -f $PWD/.besu.lock ];then
    echo "ATENÇÃO: Arquivo .lock não encontrado. Certifique-se de que o setup inicial já foi executado." >&2
    exit 1
fi

compose=$(cat $PWD/.besu.lock)

if [[ "$compose" == "swarm" ]];then
    echo "Executando deploy de stack com nome \"besu\""
    docker stack deploy -c docker-compose.yaml besu
else
    echo "Executando docker-compose"
    docker compose up -d
fi

