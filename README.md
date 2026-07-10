# 🚀 Nextcloud Deployment Tool: Híbrido Corporativo (Online/Offline)

Este repositório contém um script de automação em Bash para implantar uma infraestrutura completa do **Nextcloud** focada em ambientes corporativos. A arquitetura foi desenhada para ser resiliente a falhas de internet, permitindo o acesso seguro via HTTPS tanto externamente quanto localmente na rede interna (Modo Offline).

## 🏗️ Arquitetura do Sistema

A solução utiliza uma stack multi-container em Docker integrada a serviços da Cloudflare:

1. **Nextcloud (FPM):** Core da aplicação rodando em modo de alta performance.
2. **PostgreSQL 15:** Banco de dados relacional robusto.
3. **Nginx Proxy Manager (NPM):** Proxy reverso local que gerencia o tráfego e emite certificados SSL válidos via desafio DNS.
4. **Cloudflare Tunnel (`cloudflared`):** Cria um canal seguro de comunicação entre o servidor local e a nuvem da Cloudflare, eliminando a necessidade de abrir portas no roteador/firewall (CGNAT-ready).

---

## 🛠️ Pré-requisitos e Preparação (Cloudflare)

Antes de rodar o script no seu servidor Ubuntu 24.04, configure o seu painel da Cloudflare:

### 1. Criar o Token de API para SSL Local
Para que o servidor local emita certificados SSL oficiais de forma automatizada, crie um token de acesso:
1. No painel da Cloudflare, vá em **Meu Perfil** > **Tokens de API**.
2. Clique em **Criar token** e use o modelo **Editar DNS da zona** (*Edit zone DNS*).
3. Em *Zone Resources*, mude para: `Incluir` > `Zona específica` > Selecione seu domínio (ex: `seudominio.com.br`).
4. Salve e copie o Token gerado.

### 2. Criar o Túnel e a Rota Pública
1. No painel Zero Trust da Cloudflare, acesse **Redes** > **Conectores**.
2. Clique em **+ Criar um túnel**, escolha o tipo `Cloudflared` e dê um nome a ele.
3. Copie o **Token do Túnel** gerado.
4. Clique para editar o túnel criado, vá na aba **Rotas de aplicativos publicados** e clique em **Adicionar rota de aplicativo publicado**:
   * **Subdomínio:** O prefixo desejado (ex: `nuvem`).
   * **Domínio:** Seu domínio principal.
   * **Tipo de serviço:** `HTTP`
   * **URL:** `nginx-proxy-manager:80`

---

## 🚀 Como Executar o Deploy Automatizado

Acesse o terminal do seu servidor Ubuntu Server 24.04, clone este repositório ou crie o script manualmente e execute os comandos abaixo:

```bash
# Dar permissão de execução ao script
chmod +x deploy.sh

# Executar o instalador automatizado
./deploy.sh
