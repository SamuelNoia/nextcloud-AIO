#!/bin/bash

# Cores para o terminal
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

clear
echo -e "${VERDE}=======================================================${NC}"
echo -e "${VERDE}     SCRIPT DE IMPLANTAÇÃO AUTOMÁTICA - NEXTCLOUD       ${NC}"
echo -e "${VERDE}=======================================================${NC}\n"

# ==========================================
# 1. VALIDAÇÃO DE PRÉ-REQUISITOS E SOLUÇÃO
# ==========================================
echo -e "${AMARELO}[1/4] Validando portas do sistema (80, 443, 81)...${NC}"
CONFLITO=0

for PORTA in 80 443 81; do
    PID_CONFLITO=$(sudo lsof -t -i :$PORTA -sTCP:LISTEN 2>/dev/null)
    if [ ! -z "$PID_CONFLITO" ]; then
        PROCESSO_NOME=$(ps -p $PID_CONFLITO -o comm=)
        echo -e "${VERMELHO}⚠ CONFLITO DETECTADO: A porta $PORTA está ocupada pelo processo: '$PROCESSO_NOME'.${NC}"
        CONFLITO=$((CONFLITO + 1))
        
        if [[ "$PROCESSO_NOME" == "nginx" || "$PROCESSO_NOME" == "apache2" ]]; then
            read -p "Deseja que o script pare e desative o '$PROCESSO_NOME' automaticamente? [s/N]: " RESP
            if [[ "$RESP" =~ ^([sS][iI][mM]|[sS])$ ]]; then
                sudo systemctl stop $PROCESSO_NOME
                sudo systemctl disable $PROCESSO_NOME
                echo -e "${VERDE}✔ $PROCESSO_NOME desativado com sucesso!${NC}"
                CONFLITO=$((CONFLITO - 1))
            fi
        else
            read -p "Deseja forçar a finalização do processo PID $PID_CONFLITO? [s/N]: " RESP_KILL
            if [[ "$RESP_KILL" =~ ^([sS][iI][mM]|[sS])$ ]]; then
                sudo kill -9 $PID_CONFLITO
                echo -e "${VERDE}✔ Processo $PID_CONFLITO finalizado.${NC}"
                CONFLITO=$((CONFLITO - 1))
            fi
        fi
    fi
done

if [ $CONFLITO -gt 0 ]; then
    echo -e "${VERMELHO}❌ Libere as portas manualmente antes de executar novamente.${NC}"
    exit 1
fi
echo -e "${VERDE}✔ Todas as portas estão livres.${NC}\n"

# ==========================================
# 2. SELEÇÃO DO ARMAZENAMENTO (MENU INTERATIVO)
# ==========================================
echo -e "${AMARELO}[2/4] Configuração de Armazenamento Inteligente...${NC}"
echo -e "Detectando pontos de montagem válidos no sistema..."
echo -e "--------------------------------------------------"

# Captura apenas os pontos de montagem válidos (excluindo /boot, loops e partições irrelevantes)
MAPAS_MONTAGEM=($(df -h --type=ext4 --type=xfs --type=btrfs 2>/dev/null | awk 'NR>1 {print $6}' | grep -v '^/boot'))

if [ ${#MAPAS_MONTAGEM[@]} -eq 0 ]; then
    echo -e "${VERMELHO}❌ Nenhum ponto de montagem compatível foi encontrado automaticamente.${NC}"
    echo -e "Usando a raiz [/] por padrão."
    MAPAS_MONTAGEM=("/")
fi

# 2.1 DISCO DE ALTA VELOCIDADE (BANCO DE DADOS E CONFIGS)
while true; do
    echo -e "\n${AMARELO}Passo A: Escolha o local para os dados de VELOCIDADE (PostgreSQL e Proxy):${NC}"
    for i in "${!MAPAS_MONTAGEM[@]}"; do
        DETALHE_DISCO=$(df -h "${MAPAS_MONTAGEM[$i]}" | tail -n 1 | awk '{print "Espaço Total: " $2 " | Disponível: " $4}')
        echo -e "  [ $((i+1)) ] Ponto de montagem: ${VERDE}${MAPAS_MONTAGEM[$i]}${NC} (${DETALHE_DISCO})"
    done
    
    read -p "Selecione uma opção (1-${#MAPAS_MONTAGEM[@]}): " OPCAO_A
    
    if [[ "$OPCAO_A" =~ ^[0-9]+$ ]] && [ "$OPCAO_A" -ge 1 ] && [ "$OPCAO_A" -le "${#MAPAS_MONTAGEM[@]}" ]; then
        PATH_VELOCIDADE="${MAPAS_MONTAGEM[$((OPCAO_A-1))]}"
        break
    else
        echo -e "${VERMELHO}❌ Opção inválida. Digite apenas o número correspondente.${NC}"
    fi
done

# 2.2 DISCO DE GRANDE CAPACIDADE (ARQUIVOS DO NEXTCLOUD)
while true; do
    echo -e "\n${AMARELO}Passo B: Escolha o local do disco GRANDE para os arquivos dos usuários (Massa):${NC}"
    for i in "${!MAPAS_MONTAGEM[@]}"; do
        DETALHE_DISCO=$(df -h "${MAPAS_MONTAGEM[$i]}" | tail -n 1 | awk '{print "Espaço Total: " $2 " | Disponível: " $4}')
        echo -e "  [ $((i+1)) ] Ponto de montagem: ${VERDE}${MAPAS_MONTAGEM[$i]}${NC} (${DETALHE_DISCO})"
    done
    
    read -p "Selecione uma opção (1-${#MAPAS_MONTAGEM[@]}): " OPCAO_B
    
    if [[ "$OPCAO_B" =~ ^[0-9]+$ ]] && [ "$OPCAO_B" -ge 1 ] && [ "$OPCAO_B" -le "${#MAPAS_MONTAGEM[@]}" ]; then
        PATH_MASSA="${MAPAS_MONTAGEM[$((OPCAO_B-1))]}"
        break
    else
        echo -e "${VERMELHO}❌ Opção inválida. Digite apenas o número correspondente.${NC}"
    fi
done

# ORGANIZAÇÃO DE PASTAS
echo -e "\n${AMARELO}Definição do nome do projeto comercial:${NC}"
read -p "Digite o nome da pasta do projeto [ENTER para 'nextcloud-prod']: " NOME_PASTA
NOME_PASTA=${NOME_PASTA:-nextcloud-prod}

BASE_VELOCIDADE="${PATH_VELOCIDADE%/}/${NOME_PASTA}/performance"
BASE_MASSA="${PATH_MASSA%/}/${NOME_PASTA}/arquivos"

echo -e "\n${AMARELO}Criando diretórios físicos estruturados...${NC}"
# O comando mkdir -p já previne falhas se os diretórios já existirem
sudo mkdir -p "$BASE_VELOCIDADE/postgres"
sudo mkdir -p "$BASE_VELOCIDADE/npm/config"
sudo mkdir -p "$BASE_VELOCIDADE/npm/letsencrypt"
sudo mkdir -p "$BASE_MASSA"

# Garante a permissão correta de escrita para o container (UID 33)
sudo chown -R 33:33 "$BASE_MASSA"

echo -e "${VERDE}✔ Estrutura de Performance verificada/criada em: $BASE_VELOCIDADE${NC}"
echo -e "${VERDE}✔ Estrutura de Arquivos verificada/criada em: $BASE_MASSA${NC}\n"

# ==========================================
# 3. COLETA DE PARÂMETROS DA EMPRESA
# ==========================================
echo -e "${AMARELO}[3/4] Coleta de parâmetros de configuração...${NC}"
read -p "Digite o domínio completo configurado na Cloudflare (ex: nuvem.segtec.online): " DOMINIO
read -p "Digite o Token do Túnel Cloudflare (obtido no painel): " CLOUDFLARE_TOKEN
read -p "Digite o usuário administrador do Nextcloud [admin]: " NC_USER
NC_USER=${NC_USER:-admin}
read -p "Digite a senha do administrador do Nextcloud: " NC_PASS

DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

REDE_NOME="nextcloud-network"
if [ $(docker network ls 2>/dev/null | grep -c "$REDE_NOME") -eq 0 ]; then
    docker network create --driver bridge "$REDE_NOME"
fi

# ==========================================
# 4. GERAÇÃO DINÂMICA DO DOCKER-COMPOSE
# ==========================================
echo -e "\n${AMARELO}[4/4] Gerando o arquivo docker-compose.yml personalizado...${NC}"

cat <<EOF > docker-compose.yml
version: '3.8'

services:
  nextcloud-db:
    image: postgres:15-alpine
    container_name: nextcloud-db
    restart: always
    volumes:
      - $BASE_VELOCIDADE/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=$DB_PASS
    networks:
      - $REDE_NOME

  nextcloud-app:
    image: nextcloud:production-fpm
    container_name: nextcloud-app
    restart: always
    depends_on:
      - nextcloud-db
    volumes:
      - $BASE_VELOCIDADE/app_system:/var/www/html
      - $BASE_MASSA:/var/www/html/data
    environment:
      - POSTGRES_HOST=nextcloud-db
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=$DB_PASS
      - NEXTCLOUD_ADMIN_USER=$NC_USER
      - NEXTCLOUD_ADMIN_PASSWORD=$NC_PASS
      - NEXTCLOUD_TRUSTED_DOMAINS=$DOMINIO
    networks:
      - $REDE_NOME

  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - $BASE_VELOCIDADE/npm/config:/data
      - $BASE_VELOCIDADE/npm/letsencrypt:/etc/letsencrypt
    depends_on:
      - nextcloud-app
    networks:
      - $REDE_NOME

  cloudflare-tunnel:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-nextcloud-tunnel
    restart: always
    command: tunnel --no-autoupdate run --token $CLOUDFLARE_TOKEN
    depends_on:
      - nginx-proxy-manager
    networks:
      - $REDE_NOME

networks:
  $REDE_NOME:
    external: true
EOF

echo -e "${VERDE}✔ Arquivo docker-compose.yml configurado perfeitamente!${NC}"
echo -e "${AMARELO}Iniciando a stack de containers...${NC}"

sudo docker compose up -d

echo -e "\n${VERDE}=======================================================${NC}"
echo -e "${VERDE}   IMPLANTAÇÃO CONCLUÍDA COM SUCESSO!                  ${NC}"
echo -e "${VERDE}=======================================================${NC}"
echo -e "Acesse o painel do Proxy local: http://IP_DO_SERVIDOR:81 para ativar o SSL."
