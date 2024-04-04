# Gerar Configuração, genesis e chaves

Criar um arquivo .env no mesmo diretório do arquivo setup.sh
Especificar as variáveis de ambiente NUM_VALIDADORES (ex: 3), NUM_FULLNODES (ex: 1), VERSAO_BESU (ex: 23.10.1) e PARTICIPANTE(ex: serpro)

Utilizar o comando:

```
./setup.sh
```

O script solicita ao usuário se o arquivo docker-compose deve ser gerado para execução dos containers no mesmo Host ou em um cluster Docker Swarm. Certifique-se da escolha correta do ambiente de execução.

O script setup.sh deve ser utilizado uma única vez para gerar o arquivo genesis.json, e as chaves para os N nós validadores e M fullnodes.

O algoritmo cria a pasta config/ contendo o arquivo genesis.json, o arquivo config.toml contendo o campo "bootnodes" com os endereços dos nós gerados, e o arquivo permissions-config.toml especificando os nós com permissão para comunicação com os nós gerados.
As chaves geradas são movidas para ./nodes/{validador/fullnode}-{participante}-{id}.

O arquivo docker-compose.yaml é gerado para utilizar o Docker Swarm para fazer deploy dos nodes em diferentes VM's ou em um host único. No caso de ambiente de cluster Swarm, a correta execução do nó depende de cada máquinaa estar configurada como worker/manager node, possuir o hostname = {validador/fullnode}-{participante}-{id}, e possuir os diretórios /config e {validador/fullnode}-{participante}-{id} em /opt/besu

É possível sobrescrever configurações utilizando variáveis de ambiente conforme documentação do besu (https://besu.hyperledger.org/23.10.2/private-networks/reference/cli/options#specify-options) no attributo environment do arquivo docker-compose.

O script setup.sh gera os arquivos localmente. Para movê-los para as máquinas virtuais em caso de uso do Swarm, utilizar os scripts:

```
./move-keys-to-workers.sh
./move-config-to-workers.sh
```

O script que move os arquivos de configuração sobrescreve os arquivos de configuração nas máquinas virtuais se já existentes. O script que move as chaves não sobrescreve as chaves presentes nas máquinas virtuais.

Para executar a rede, é necessário executar o script run.sh a partir do host único ou do nó Master do Docker Swarm.

```
./run.sh
```
