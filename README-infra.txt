# Documentação Instalação modelo Besu

Instalar o Ubuntu
  Rede IPV4:
    subnet: 192.168.19.0/24
    Address: 192.168.19.x
    Gateway: 192.168.19.1
    Nameserver: 192.168.255.228

  Profile:
    Nome: Supis
    server-name: validador-serpro-1
    username: supis
    password: *

  Install openssh server

Istalação:
  fail2ban:
    apt install fail2ban
    vi /etc/fail2ban/jain.conf
      bantime = 24h
    systemctl enable fail2ban
    systemctl start fail2ban

  docker:
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
    newgrp docker

Copia do modelo:
  seleciona vapp
  Trocar nomes
  Selecionar política de armazenamento
  Ativar Nic, preencher:
    conectado
    tipo de rede: VMX...
    Ip estático
    Ip

Cada modelo:
  ssh supis@192.168.10.100
  hostnamectl hostname x
  sudo vi /etc/netplan/00-installer-config.yaml
  netplan apply
  refazer login
  sudo sed '/127\.0\.1\.1/s/ .*/ '"$(hostname)"'/;$a\\n192.168.10.101 validador-serpro-1\n192.168.10.102 validador-serpro-2\n192.168.10.103 validador-serpro-3\n192.168.10.104 fullnode-serpro-1' -i /etc/hosts
  # Bug VMWare Floppy
  echo "blacklist floppy" | sudo tee /etc/modprobe.d/blacklist-floppy.conf
  sudo rmmod floppy
  sudo update-initramfs -u

Infraestrutura besu em /opt
  besuroot="/opt/besu"
  sudo mkdir "${besuroot}"
  sudo chmod 777 "${besuroot}"
  git config --global --add safe.directory /opt/besu
  cd "${besuroot}"
  # No primeiro nó:
    Criar variável .env:
      echo 'VERSAO_BESU=23.10.1' >> .env
      echo 'NUM_VALIDADORES=3' >> .env
      echo 'NUM_FULLNODES=1' >> .env
    sudo setup.sh
    cp -a nodes/$HOSTNAME .

Fazer a partir do primeiro nó:
  besuroot="/opt/besu"
  cd "${besuroot}"
  ./move-config-to-workers.sh validador-serpro-2 validador-serpro-3 fullnode-serpro-1
  ./move-keys-to-workers.sh validador-serpro-2 validador-serpro-3 fullnode-serpro-1
  docker swarm init
  # entrar em cada outro nó e juntar-se ao swarm
  # Para pegar o token posteriormente: docker swarm join-token worker
