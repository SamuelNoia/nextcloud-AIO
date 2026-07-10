# Nextcloud AIO - Implantação Automatizada Multi-Disco

Este repositório contém o script de implantação automatizada para o Nextcloud em ambiente de produção, otimizado para servidores com armazenamento híbrido (SSD para performance + HD para alta capacidade) e integrado nativamente com Cloudflare Tunnels e Nginx Proxy Manager.

---

## 🚀 Próximos Passos (Pós-Implantação)

Assim que o script `deploy.sh` finalizar a execução e exibir a mensagem de sucesso, a estrutura de containers estará rodando. Siga estes passos para colocar o sistema em produção:

### 1. Configurar o Roteamento no Painel da Cloudflare
Como você já possui o conector ativo e saudável no painel (Zero Trust), você precisa apontar o seu subdomínio para o container interno:
1. Acesse o menu **Redes > Conectores (Tunnels)** no painel do Cloudflare Zero Trust.
2. Clique no seu túnel ativo e vá em **Rotas de aplicativos publicados > Adicionar rota**.
3. Configure os campos exatamente assim:
   * **Subdomínio:** O subdomínio desejado (ex: `nuvem` ou `nextcloud`).
   * **Domínio:** `segtec.online`.
   * **Caminho (Optional):** Deixe em branco.
   * **Serviço (Tipo):** Escolha `HTTP`.
   * **URL:** Digite `nginx-proxy-manager:80` (O túnel falará diretamente com o proxy através da rede isolada do Docker).

### 2. Configurar o Proxy Reverso (Nginx Proxy Manager)
1. Abra no seu navegador o endereço: `http://IP_DO_SEU_SERVIDOR:81`.
2. Os dados de acesso padrão do Nginx Proxy Manager são:
   * **Email:** `admin@example.com`
   * **Password:** `changeme`
3. O painel solicitará imediatamente que você altere o e-mail e a senha administrativa. **Guarde esses novos dados.**
4. Vá em **Hosts > Proxy Hosts > Add Proxy Host** e configure:
   * **Domain Names:** O seu domínio completo (ex: `nuvem.segtec.online`).
   * **Scheme:** `http`
   * **Forward Hostname / IP:** `nextcloud-app`
   * **Forward Port:** `80`
   * Marque as opções: *Websockets Support*, *Block Common Exploits* e *Force SSL*.

---

## 📁 Estrutura de Armazenamento Inteligente

O script organiza automaticamente os diretórios baseando-se na sua escolha numérica durante a instalação, separando os dados por tipo de uso:

* **Performance (SSD / Raiz):** Onde ficam os arquivos do banco de dados (PostgreSQL), logs e configurações do Nginx Proxy Manager. Garante que a busca por arquivos e cache seja instantânea.
* **Massa de Dados (HD Externo / `/mnt/armazenamento`):** Onde os arquivos pesados enviados pelos usuários (fotos, PDFs, backups) são guardados.

Todas as pastas internas recebem automaticamente a permissão `chown -R 33:33` correspondente ao usuário `www-data` do container Nextcloud, evitando erros de leitura/escrita.

---

## 🛠️ Comandos Úteis de Manutenção

Se precisar gerenciar a aplicação através do terminal do servidor, utilize os comandos abaixo dentro da pasta do projeto (`nextcloud-AIO`):

**Verificar o status dos containers:**
```bash
sudo docker compose ps
