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
    PID_CONFLITO=$(sudo lsof -t -i :$PORTA -sTCP:LISTEN)
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
# 2. SELEÇÃO DO ARMAZENAMENTO (PERFORMANCE x CAPACIDADE)
# ==========================================
echo -e "${AMARELO}[2/4] Configuração de Armazenamento Inteligente...${NC}"
echo -e "Discos disponíveis instalados e onde estão montados ('Mounted on'):"
echo -e "-----------------------------------------------------------------"
df -h --type=ext4 --type=xfs 2>/dev/null || df -h
echo -e "-----------------------------------------------------------------\n"

# 2.1 DISCO DE ALTA VELOCIDADE (BANCO DE DADOS E CONFIGS)
while true; do
    echo -e "${AMARELO}Passo A: Onde ficarão os dados que exigem VELOCIDADE (PostgreSQL e Proxy)?${NC}"
    read -p "Digite o ponto de montagem (Ex: / ou /mnt/ssd) [ENTER para a Raiz '/']: " PATH_VELOCIDADE
    PATH_VELOCIDADE=${PATH_VELOCIDADE:-/}

    if [ -d "$PATH_VELOCIDADE" ]; then
        break
    else
        echo -e "${VERMELHO}❌ Erro: O caminho '$PATH_VELOCIDADE' não é um diretório válido no sistema. Tente novamente.${NC}\n"
    fi
done

# 2.2 DISCO DE GRANDE CAPACIDADE (ARQUIVOS DO NEXTCLOUD)
while true; do
    echo -e "\n${AMARELO}Passo B: Onde ficará o disco GRANDE para os arquivos dos usuários (Armazenamento em Massa)?${NC}"
    read -p "Digite o ponto de montagem (Ex: /mnt/armazenamento): " PATH_MASSA

    if [ -d "$PATH_MASSA" ]; then
        break
    else
        echo -e "${VERMELHO}❌ Erro: O caminho '$PATH_MASSA' não existe ou não está montado. Tente novamente.${NC}\n"
    fi
done

# Definindo caminhos finais padronizados para não haver erros de escrita
BASE_VELOCIDADE="${PATH_VELOCIDADE%/}/nextcloud-performance"
BASE_MASSA="${PATH_MASSA%/}/nextcloud-arquivos"

echo -e "\n${AMARELO}Criando a estrutura física dos diretórios...${NC}"
mkdir -p "$BASE_VELOCIDADE/postgres"
mkdir -p "$BASE_VELOCIDADE/npm/config"
mkdir -p "$BASE_VELOCIDADE/npm/letsencrypt"
mkdir -p "$BASE_MASSA"

# Correção crucial de permissão para que o container do Nextcloud consiga gravar no HD Externo/LVM secundário
sudo chown -R 33:33 "$BASE_MASSA"

echo -e "${VERDE}✔ Diretório de Velocidade: $BASE_VELOCIDADE${NC}"
echo -e "${VERDE}✔ Diretório de Grande Capacidade: $BASE_MASSA${NC}\n"

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
      # O código do Nextcloud fica no disco rápido, mas os dados dos usuários vão para o HD Grande
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
