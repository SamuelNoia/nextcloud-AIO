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
# 1. VALIDAÇÃO DE PRÉ-REQUISITOS
# ==========================================
echo -e "${AMARELO}[1/4] Validando portas do sistema (80, 443, 81)...${NC}"
CONFLITO=0
for PORTA in 80 443 81; do
    if lsof -Pi :$PORTA -sTCP:LISTEN -t >/dev/null ; then
        echo -e "${VERMELHO}❌ ERRO: A porta $PORTA já está em uso por outro serviço local!${NC}"
        CONFLITO=$((CONFLITO + 1))
    fi
done

if [ $CONFLITO -gt 0 ]; then
    echo -e "${VERMELHO}Remova o serviço conflitante (ex: apache/nginx nativo) antes de continuar.${NC}"
    exit 1
fi
echo -e "${VERDE}✔ Portas livres detectadas.${NC}\n"

# ==========================================
# 2. SELEÇÃO DO ARMAZENAMENTO (SSD / HD)
# ==========================================
echo -e "${AMARELO}[2/4] Configuração do local de armazenamento de dados...${NC}"
echo -e "Discos disponíveis no sistema:"
df -h --type=ext4 --type=xfs 2>/dev/null || df -h

echo -e "\nInforme onde deseja salvar os dados do Nextcloud e do Banco (Ideal: Caminho do seu SSD)."
read -p "Digite o caminho absoluto (ou pressione ENTER para a pasta atual): " BASE_PATH

if [ -z "$BASE_PATH" ]; then
    BASE_PATH=$(pwd)/nextcloud-prod
else
    BASE_PATH="${BASE_PATH}/nextcloud-prod"
fi

echo -e "${AMARELO}Criando diretórios estruturados em: $BASE_PATH...${NC}"
mkdir -p "$BASE_PATH/postgres"
mkdir -p "$BASE_PATH/app"
mkdir -p "$BASE_PATH/npm/config"
mkdir -p "$BASE_PATH/npm/letsencrypt"
echo -e "${VERDE}✔ Diretórios criados com sucesso.${NC}\n"

# ==========================================
# 3. COLETA DE PARÂMETROS DA EMPRESA
# ==========================================
echo -e "${AMARELO}[3/4] Coleta de parâmetros de configuração...${NC}"
read -p "Digite o domínio completo configurado na Cloudflare (ex: nuvem.segtec.online): " DOMINIO
read -p "Digite o Token do Túnel Cloudflare (obtido no painel): " CLOUDFLARE_TOKEN
read -p "Digite o usuário administrador do Nextcloud [admin]: " NC_USER
NC_USER=${NC_USER:-admin}
read -p "Digite a senha do administrador do Nextcloud: " NC_PASS

# Gerando senhas aleatórias fortes para o banco de dados interno
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

# Criando/Verificando a rede Docker
REDE_NOME="nextcloud-network"
if [ $(docker network ls | grep -c "$REDE_NOME") -eq 0 ]; then
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
      - $BASE_PATH/postgres:/var/lib/postgresql/data
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
      - $BASE_PATH/app:/var/www/html
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
      - $BASE_PATH/npm/config:/data
      - $BASE_PATH/npm/letsencrypt:/etc/letsencrypt
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

echo -e "${VERDE}✔ Arquivo docker-compose.yml criado com sucesso na pasta atual!${NC}"
echo -e "${AMARELO}Iniciando a stack de containers...${NC}"

sudo docker compose up -d

echo -e "\n${VERDE}=======================================================${NC}"
echo -e "${VERDE}   IMPLANTAÇÃO CONCLUÍDA COM SUCESSO!                  ${NC}"
echo -e "${VERDE}=======================================================${NC}"
echo -e "Acesse o painel do Proxy local: http://IP_DO_SERVIDOR:81 para ativar o SSL."
echo -e "Após o NPM estar ativo, o túnel Cloudflare linkará o endereço automaticamente."