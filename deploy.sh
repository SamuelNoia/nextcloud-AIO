# ==========================================
# 2. SELEÇÃO DO ARMAZENAMENTO (MENU INTERATIVO)
# ==========================================
echo -e "${AMARELO}[2/4] Configuração de Armazenamento Inteligente...${NC}"
echo -e "Detectando pontos de montagem válidos no sistema..."
echo -e "--------------------------------------------------"

# Captura apenas os pontos de montagem válidos (excluindo /boot, loops e partições de sistema irrelevantes)
MAPAS_MONTAGEM=($(df -h --type=ext4 --type=xfs --type=btrfs 2>/dev/null | awk 'NR>1 {print $6}' | grep -v '^/boot'))

if [ ${#MAPAS_MONTAGEM[@]} -eq 0 ]; then
    echo -e "${VERMELHO}❌ Nenhum ponto de montagem compatível foi encontrado automaticamente.${NC}"
    echo -e "Usando a raiz [/] por padrão."
    MAPAS_MONTAGEM=("/")
fi

# --------------------------------------------------
# PASSO A: SELEÇÃO DO DISCO RÁPIDO (PERFORMANCE)
# --------------------------------------------------
while true; do
    echo -e "\n${AMARELO}Passo A: Escolha o local para os dados de VELOCIDADE (PostgreSQL e Proxy):${NC}"
    for i in "${!MAPAS_MONTAGEM[@]}"; do
        # Mostra o tamanho e espaço disponível para ajudar o técnico a decidir
        DETALHE_DISCO=$(df -h "${MAPAS_MONTAGEM[$i]}" | tail -n 1 | awk '{print "Espaço Total: " $2 " | Disponível: " $4}')
        echo -e "  [ $((i+1)) ] O ponto de montagem: ${VERDE}${MAPAS_MONTAGEM[$i]}${NC} (${DETALHE_DISCO})"
    done
    
    read -p "Selecione uma opção (1-${#MAPAS_MONTAGEM[@]}): " OPCAO_A
    
    if [[ "$OPCAO_A" =~ ^[0-9]+$ ]] && [ "$OPCAO_A" -ge 1 ] && [ "$OPCAO_A" -le "${#MAPAS_MONTAGEM[@]}" ]; then
        PATH_VELOCIDADE="${MAPAS_MONTAGEM[$((OPCAO_A-1))]}"
        break
    else
        echo -e "${VERMELHO}❌ Opção inválida. Digite apenas o número correspondente.${NC}"
    fi
done

# --------------------------------------------------
# PASSO B: SELEÇÃO DO DISCO GRANDE (MASSA DE DADOS)
# --------------------------------------------------
while true; do
    echo -e "\n${AMARELO}Passo B: Escolha o local do disco GRANDE para os arquivos dos usuários:${NC}"
    for i in "${!MAPAS_MONTAGEM[@]}"; do
        DETALHE_DISCO=$(df -h "${MAPAS_MONTAGEM[$i]}" | tail -n 1 | awk '{print "Espaço Total: " $2 " | Disponível: " $4}')
        echo -e "  [ $((i+1)) ] O ponto de montagem: ${VERDE}${MAPAS_MONTAGEM[$i]}${NC} (${DETALHE_DISCO})"
    done
    
    read -p "Selecione uma opção (1-${#MAPAS_MONTAGEM[@]}): " OPCAO_B
    
    if [[ "$OPCAO_B" =~ ^[0-9]+$ ]] && [ "$OPCAO_B" -ge 1 ] && [ "$OPCAO_B" -le "${#MAPAS_MONTAGEM[@]}" ]; then
        PATH_MASSA="${MAPAS_MONTAGEM[$((OPCAO_B-1))]}"
        break
    else
        echo -e "${VERMELHO}❌ Opção inválida. Digite apenas o número correspondente.${NC}"
    fi
done

# --------------------------------------------------
# ORGANIZAÇÃO DE PASTAS PERSONALIZADAS
# --------------------------------------------------
echo -e "\n${AMARELO}Por padrão, criaremos as pastas estruturadas dentro desses caminhos.${NC}"
read -p "Deseja definir um nome personalizado para a pasta do projeto? [ENTER para 'nextcloud-prod']: " NOME_PASTA
NOME_PASTA=${NOME_PASTA:-nextcloud-prod}

# Garante a remoção de barras extras no final do caminho para evitar erros de sintaxe no Linux
BASE_VELOCIDADE="${PATH_VELOCIDADE%/}/${NOME_PASTA}/performance"
BASE_MASSA="${PATH_MASSA%/}/${NOME_PASTA}/arquivos"

echo -e "\n${AMARELO}Criando diretórios físicos no servidor...${NC}"
sudo mkdir -p "$BASE_VELOCIDADE/postgres"
sudo mkdir -p "$BASE_VELOCIDADE/npm/config"
sudo mkdir -p "$BASE_VELOCIDADE/npm/letsencrypt"
sudo mkdir -p "$BASE_MASSA"

# Permissão correta para o container do Nextcloud rodar sem erros de escrita (UID do container é 33)
sudo chown -R 33:33 "$BASE_MASSA"

echo -e "${VERDE}✔ Estrutura de Performance criada em: $BASE_VELOCIDADE${NC}"
echo -e "${VERDE}✔ Estrutura de Arquivos criada em: $BASE_MASSA${NC}\n"
