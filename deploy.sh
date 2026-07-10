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
        DETALHE_DISCO
