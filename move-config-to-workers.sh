#!/bin/bash
hosts="$@"
if [ -z "$hosts" ]; then
  echo "Falta parâmetros dos hostnames (como em /etc/hosts)."
  exit 1
fi

#Verifica se setup já foi executado
if [ ! -f $PWD/.besu.lock ];then
    echo "ATENÇÃO: Arquivo .lock não encontrado. Certifique-se de que o setup inicial já foi executado." >&2
    exit 1
fi

compose=$(cat $PWD/.besu.lock)

if [[ "$compose" == "swarm" ]];then
  echo "Copiando config para os workers..."
  for d in $@; do
    echo "Copiando config para $d"
    if [ "$d" == "$(hostname)" ];then
      cp -r $PWD/config /opt/besu 
    else
      rsync -ahHP $PWD/config supis@$d:/opt/besu
    fi
  done
else
    echo "Atenção: arquivo setup.sh executado com opção \"Host\". Leia a documentação e utilize opção \"Swarm\" para fazer deploy em diferentes Workers."
    exit 1
fi

