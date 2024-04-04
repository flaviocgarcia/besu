#!/bin/bash

#Source variáveis de ambiente
[ -s ".env" ] && . ./.env
_sair=false

if [ -z "${VERSAO_BESU}" ]; then
    echo "Variável de ambiente VERSAO_BESU ausente. Especifique a variável em um arquivo .env neste mesmo diretório."
    _sair=true
fi
if [ -z "${NUM_VALIDADORES}" ]; then
    echo "Variável de ambiente NUM_VALIDADORES ausente. Especifique a variável em um arquivo .env neste mesmo diretório."
    _sair=true
fi
if [ -z "${NUM_FULLNODES}" ]; then
    echo "Variável de ambiente NUM_FULLNODES ausente. Especifique a variável em um arquivo .env neste mesmo diretório."
    _sair=true
fi
if [ -z "${PARTICIPANTE}" ]; then
    echo "Variável de ambiente PARTICIPANTE ausente. Especifique a variável em um arquivo .env neste mesmo diretório."
    _sair=true
fi
$_sair && exit 1

# Seleciona se quer gerar docker-compose para deploy em swarm ou deploy local
PS3="Gerar docker-compose.yml para execução:"

select lng in Host Swarm Cancelar
do
    case $lng in
        "Host")
            compose="host"
            break;;
        "Swarm")
            compose="swarm"
            break;;
        "Cancelar")
           exit 1;;
        *)
           echo "Invalido";;
    esac
done

besu_version=${VERSAO_BESU}
# numero de nós
num_validadores=${NUM_VALIDADORES}
num_fullnodes=${NUM_FULLNODES}
participante=${PARTICIPANTE}

# Verifica se foi especificado pelo menos 1 validador
if [ $num_validadores -lt 1 ]; then
    echo "O numéro de validadores espeficiado ($num_validadores) deve ser de pelo menos 1."
    exit 1
fi
# Verifica se foi especificado pelo menos 1 fullnode
if [ $num_fullnodes -lt 1 ]; then
    echo "O numéro de validadores espeficiado ($num_fullnodes) deve ser de pelo menos 1."
    exit 1
fi

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "Docker não encontrado. Por favor instale o Docker e tente novamente."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Docker não está executando ou usuário não tem permissões. Resolva e tente novamente."
    exit 1
fi

echo "Docker instalado e executando."

# Gera bloco genesis para N validadores, gera chaves para validadores
generate_genesis_keys_validadores() {
    echo "Gerando arquivo genesis.json, config.toml e chaves dos nós validadores..."
    mkdir -p config && sudo chmod ugo+w config && cp ./genesisGeneratorFile.json config/genesisGeneratorFile.json
    sed -i "s/<NUMBER_NODES>/$num_validadores/g" ./config/genesisGeneratorFile.json
    cp ./configModel.toml ./config/config.toml
    docker run --rm -v $PWD/config:/opt/besu/config hyperledger/besu:$besu_version operator generate-blockchain-config --config-file=/opt/besu/config/genesisGeneratorFile.json --to=/opt/besu/config/validatorFiles --private-key-file-name=key
    sudo mv config/validatorFiles/genesis.json ./config/genesis.json
    sudo rm -rf config/genesisGeneratorFile.json
    echo "Gerado com sucesso."
}

# Gera par de chaves para N fullnodes
generate_keys_fullnode() {
    echo "Gerando chaves para nós fullnode..."
    mkdir -p config && sudo chmod ugo+w config && cp ./genesisGeneratorFile.json config/genesisGeneratorFile.json
    sed -i "s/<NUMBER_NODES>/$num_fullnodes/g" ./config/genesisGeneratorFile.json
    docker run --rm -v $PWD/config:/opt/besu/config hyperledger/besu:$besu_version operator generate-blockchain-config --config-file=/opt/besu/config/genesisGeneratorFile.json --to=/opt/besu/config/fullnodeFiles --private-key-file-name=key
    sudo rm -rf config/genesisGeneratorFile.json
    echo "Gerado com sucesso"
}

# Move as chaves geradas para as pastas dos validadores e fullnodes. Modifica os arquivos de config e permissão para incluir bootnodes e allowlist com endereços dos nós
move_keys() {
    echo "Movendo chaves..."
    bootnodes="bootnodes = ["
    nodes_allowlist="nodes-allowlist = ["
    total_nodes=$(($num_validadores + $num_fullnodes))

    for (( i=1; i<=num_validadores; i++ ))
    do
        directory=$(ls $PWD/config/validatorFiles/keys/ | head -$i | tail -1)
        node_id=$(cat $PWD/config/validatorFiles/keys/$directory/key.pub| sed 's/^0x//')
        # bootnodes+="\"enode://$node_id@172.16.240.$((30+i-1)):30303\""
        bootnodes+="\"enode://$node_id@validador-$participante-$i:30303\", "
        nodes_allowlist+="\"enode://$node_id@validador-$participante-$i:30303\", "
        sudo mv $PWD/config/validatorFiles/keys/$directory/* $PWD/nodes/validador-$participante-$i/data
        echo "Chaves validador-$participante-$i movidas com sucesso."
    done

    for (( i=1; i<=num_fullnodes; i++ ))
    do
        directory=$(ls $PWD/config/fullnodeFiles/keys/ | head -$i | tail -1)
        node_id=$(cat $PWD/config/fullnodeFiles/keys/$directory/key.pub| sed 's/^0x//')
        # bootnodes+="\"enode://$node_id@172.16.240.$((30+i-1)):30303\""
        bootnodes+="\"enode://$node_id@fullnode-$participante-$i:30303\", "
        nodes_allowlist+="\"enode://$node_id@fullnode-$participante-$i:30303\", "
        sudo mv $PWD/config/fullnodeFiles/keys/$directory/* $PWD/nodes/fullnode-$participante-$i/data
        echo "Chaves fullnode-$participante-$i movidas com sucesso."
    done

    bootnodes="$(sed 's/[ ,]*$/]/' <<< "$bootnodes")"
    nodes_allowlist="$(sed 's/[ ,]*$/]/' <<< "$nodes_allowlist")"

    echo "$bootnodes" >> $PWD/config/config.toml
    echo "$nodes_allowlist" >> $PWD/config/permissions-config.toml
    echo "Adicionado \"bootnodes\" em config.toml e gerado arquivo permissions-config.toml"
    sudo rm -rf keys config/fullnodeFiles config/validatorFiles
}

# Create a directory for config if it doesn't exist
echo "Setting up configuration..."
if [ -f $PWD/.besu.lock ];then
    echo "ATENÇÃO: Há um arquivo de LOCK presente. A presença do arquivo LOCK indica que o setup já foi realizado e já existem chaves e arquivo genesis gerados para a rede Besu." >&2
    echo "Para executar o script, remova o arquivo .besu.lock. A execução do script substitui as chaves e arquivo genesis gerados anteriormente." >&2
    exit 1
fi
echo "$compose" > $PWD/.besu.lock

echo "Gerando docker-compose.yaml"

# Gera arquivo docker-compose.yaml
if [[ "$compose" == "swarm" ]];then
    cat > docker-compose.yaml << EOF
version: "3.6"

networks:
  host:
    name: host
    external: true

services:
EOF
else
    cat > docker-compose.yaml << EOF
version: "3.6"

networks:
  besu-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.240.0/24

services:
EOF
fi

# Loop to setup each node
echo "Criando diretórios para os nós..."
index=0
if [[ "$compose" == "swarm" ]];then
    config_path=/opt/besu/config
    nodes_path=/opt/besu
    explorer_path=/opt/besu/quorum-explorer
else
    config_path=./config
    nodes_path=./nodes
    explorer_path=./quorum-explorer
fi
fullnome=""
for node_dir in $(eval echo "validador-$participante-{1..$num_validadores}" \
                     "fullnode-$participante-{1..$num_fullnodes}"); do
    # generate_keys $node_dir
    echo $node_dir
    mkdir -p nodes/$node_dir/data && sudo chmod ugo+w -R nodes/$node_dir

    cat >> docker-compose.yaml << EOF
    $node_dir:
        container_name: $node_dir
        image: hyperledger/besu:$besu_version
        entrypoint:
            - /bin/bash
            - -c
            - |
                sleep $((index*10));
                /opt/besu/bin/besu \
                --config-file=/opt/besu/config.toml
        volumes:
            - $config_path/config.toml:/opt/besu/config.toml
            - $config_path/genesis.json:/opt/besu/genesis.json
            - $config_path/permissions-config.toml:/opt/besu/permissions-config.toml
            - $nodes_path/$node_dir/data:/opt/besu/data
        environment:
            - BESU_IDENTITY=$node_dir
EOF
    if [[ "$node_dir" == *"fullnode"* ]];then
        cat >> docker-compose.yaml << EOF
            - BESU_RPC_HTTP_ENABLED=true
EOF
    fi
    if [[ "$compose" == "swarm" ]];then
        fullnome="http://$node_dir:8545"
        cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == $node_dir
EOF
    else
        fullnome="http://$node_dir:8545"
        cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
        ports:
            - 303$((10+index)):30303
            - 85$((40+index)):8545
            - 95$((40+index)):9545
EOF
    fi
    index=$((index+1))
done

#Adiciona Explorer no docker-compose
# cat >> docker-compose.yaml << EOF
#     explorer:
#         image: consensys/quorum-explorer:latest
#         volumes:
#             - $explorer_path/config.json:/app/config.json
#             - $explorer_path/.env:/app/.env.production
#         depends_on:
#             - fullnode-$participante-1
# EOF
# if [[ "$compose" == "swarm" ]];then
#     cat >> docker-compose.yaml << EOF
#         networks:
#             - host
#         deploy:
#             placement:
#                 constraints:
#                     - node.hostname == explorer
# EOF
# else
#     cat >> docker-compose.yaml << EOF
#         networks:
#             besu-network:
#                 ipv4_address: 172.16.240.$((30+index))
#         ports:
#             - 25000:25000/tcp
# EOF
# fi

index=$((index+1))
#Adiciona Redis BlockScout
cat >> docker-compose.yaml << EOF
    redis-db:
        extends:
            file: ./blockscout/services/redis.yml
            service: redis-db
        depends_on:
            - fullnode-$participante-1
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona DB-INIT BlockScout
cat >> docker-compose.yaml << EOF
    db-init:
        extends:
            file: ./blockscout/services/db.yml
            service: db-init
        depends_on:
            - fullnode-$participante-1
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona DB BlockScout
cat >> docker-compose.yaml << EOF
    db:
        depends_on:
            db-init:
                condition: service_completed_successfully
        extends:
            file: ./blockscout/services/db.yml
            service: db
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona Backend BlockScout
cat >> docker-compose.yaml << EOF
    backend:
        depends_on:
            - db
            - redis-db
            - fullnode-serpro-1
        extends:
            file: ./blockscout/services/backend.yml
            service: backend
        build:
            context: ..
            dockerfile: ./docker/Dockerfile
            args:
                CACHE_EXCHANGE_RATES_PERIOD: ""
                API_V1_READ_METHODS_DISABLED: "false"
                DISABLE_WEBAPP: "false"
                API_V1_WRITE_METHODS_DISABLED: "false"
                CACHE_TOTAL_GAS_USAGE_COUNTER_ENABLED: ""
                CACHE_ADDRESS_WITH_BALANCES_UPDATE_INTERVAL: ""
                NETWORK: "DREX"
                SUBNETWORK: "DREX Demo"
                ADMIN_PANEL_ENABLED: ""
                RELEASE_VERSION: 6.3.0
        links:
            - db:database
        environment:
            ETHEREUM_JSONRPC_HTTP_URL: $fullnome
            ETHEREUM_JSONRPC_TRACE_URL: $fullnome
            CHAIN_ID: '381660001'
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona Visualizer BlockScout
cat >> docker-compose.yaml << EOF
    visualizer:
        extends:
            file: ./blockscout/services/visualizer.yml
            service: visualizer
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona Sig Provider BlockScout
cat >> docker-compose.yaml << EOF
    sig-provider:
        extends:
            file: ./blockscout/services/sig-provider.yml
            service: sig-provider
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona frontend BlockScout
cat >> docker-compose.yaml << EOF
    frontend:
        depends_on:
            - backend
        extends:
            file: ./blockscout/services/frontend.yml
            service: frontend
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona stats-db-init BlockScout
cat >> docker-compose.yaml << EOF
    stats-db-init:
        extends:
            file: ./blockscout/services/stats.yml
            service: stats-db-init
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona stats-db BlockScout
cat >> docker-compose.yaml << EOF
    stats-db:
        depends_on:
            stats-db-init:
                condition: service_completed_successfully
        extends:
            file: ./blockscout/services/stats.yml
            service: stats-db

EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona stats BlockScout
cat >> docker-compose.yaml << EOF
    stats:
        depends_on:
            - stats-db
            - backend
        extends:
            file: ./blockscout/services/stats.yml
            service: stats
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

index=$((index+1))
#Adiciona proxy BlockScout
cat >> docker-compose.yaml << EOF
    proxy:
        depends_on:
            - backend
            - frontend
            - stats
        extends:
            file: ./blockscout/services/nginx.yml
            service: proxy
EOF
if [[ "$compose" == "swarm" ]];then
    cat >> docker-compose.yaml << EOF
        networks:
            - host
        deploy:
            placement:
                constraints:
                    - node.hostname == explorer
EOF
else
    cat >> docker-compose.yaml << EOF
        networks:
            besu-network:
                ipv4_address: 172.16.240.$((30+index))
EOF
fi

generate_genesis_keys_validadores
generate_keys_fullnode
move_keys

echo "Setup Completo."
