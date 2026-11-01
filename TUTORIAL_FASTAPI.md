# Tutorial: Gerenciando uma API FastAPI com o Kong Gateway

Este tutorial mostra como configurar o Kong para atuar como API Gateway na frente
da API FastAPI publicada em `http://mtdash-api.desenv.cge.mt.gov.br`.

---

## Visão geral da arquitetura

```
Cliente
  │
  ▼
Kong Gateway (localhost:8000)
  │  ├── autenticação
  │  ├── rate limiting
  │  ├── logs
  │  └── roteamento
  ▼
FastAPI (mtdash-api.desenv.cge.mt.gov.br)
```

O Kong recebe todas as requisições, aplica plugins (segurança, limites, logs) e
faz o proxy para a API FastAPI real.

---

## Estrutura de rotas desta API

A FastAPI possui dois grupos de caminhos distintos:

| Caminho | Descrição | Autenticação |
|---------|-----------|--------------|
| `/docs` | Swagger UI | pública |
| `/redoc` | Redoc | pública |
| `/openapi.json` | Schema OpenAPI | pública |
| `/api/v1/...` | Endpoints da API | protegida |

Por isso são necessárias **duas rotas separadas** no Kong — uma pública e uma protegida.

---

## 1. Subindo o ambiente

Com o `docker-compose.yml` configurado com Postgres por padrão, basta executar:

```shell
$ docker compose up -d
```

Aguarde todos os contêineres ficarem saudáveis:

```shell
$ docker compose ps
```

O Kong estará pronto quando o contêiner `kong` aparecer como `healthy`.

A partir daqui, você pode configurar serviços e rotas de três formas:

| Forma | Quando usar |
|-------|-------------|
| **Kong Manager** `http://localhost:8002` | Interface visual, ideal para exploração e testes |
| **Admin API** `http://localhost:8001` | Automação via scripts ou ferramentas como Insomnia/Postman |
| **`kong.yaml`** | Configuração como código, ideal para versionamento no Git |

---

## 2. Configuração via kong.yaml

> Se preferir usar o Kong Manager visualmente, pule para a **seção 10**.

Crie ou edite o arquivo `config/kong.yaml`:

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    routes:
      - name: mtdash-rota
        paths:
          - /
        strip_path: false
```

Com isso, todo tráfego é encaminhado preservando o caminho completo:
- `localhost:8000/docs` → `mtdash-api.desenv.cge.mt.gov.br/docs`
- `localhost:8000/openapi.json` → `mtdash-api.desenv.cge.mt.gov.br/openapi.json`
- `localhost:8000/api/v1/...` → `mtdash-api.desenv.cge.mt.gov.br/api/v1/...`

Reinicie o Kong para aplicar:

```shell
$ docker compose down && docker compose up -d
```

Teste:

```shell
$ curl http://localhost:8000/docs
```

---

## 3. Expondo o Swagger/Docs da FastAPI pelo Kong

Com o Kong configurado, acesse pelo proxy:

- `http://localhost:8000/docs` — Swagger UI
- `http://localhost:8000/redoc` — Redoc
- `http://localhost:8000/openapi.json` — schema OpenAPI
- `http://localhost:8000/api/v1/...` — endpoints da API

---

## 4. Adicionando Rate Limiting

Evita abuso da API limitando o número de requisições por cliente.

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    plugins:
      - name: rate-limiting
        config:
          minute: 60
          hour: 1000
          policy: local
    routes:
      - name: mtdash-rota
        paths:
          - /
        strip_path: false
```

Quando o limite for atingido, o Kong retorna `HTTP 429 Too Many Requests`.

---

## 5. Adicionando autenticação com API Key

> **Importante:** o plugin `key-auth` aplicado no **serviço** bloqueia todas as rotas,
> incluindo `/docs`. Para manter o Swagger público, o plugin deve ser aplicado
> apenas na rota `/api`, não no serviço.

### Via kong.yaml

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    routes:

      # Rota 1 — pública, sem autenticação
      - name: mtdash-docs
        paths:
          - /docs
          - /redoc
          - /openapi.json
        strip_path: false

      # Rota 2 — protegida, exige X-API-Key
      - name: mtdash-endpoints
        paths:
          - /api
        strip_path: false
        plugins:
          - name: key-auth
            config:
              key_names:
                - X-API-Key

consumers:
  - username: app-frontend
    keyauth_credentials:
      - key: minha-chave-secreta-123
```

### Via Admin API

```shell
# 1. Adicionar o plugin key-auth na rota mtdash-endpoints
$ curl -X POST http://localhost:8001/routes/mtdash-endpoints/plugins \
  -d "name=key-auth" \
  -d "config.key_names[]=X-API-Key"

# 2. Criar o consumer
$ curl -X POST http://localhost:8001/consumers \
  -d "username=app-frontend"

# 3. Criar a chave para o consumer
# Deixe o campo key em branco para gerar automaticamente
$ curl -X POST http://localhost:8001/consumers/app-frontend/key-auth \
  -d "key=minha-chave-secreta-123"
```

### Via Kong Manager

**Passo 1 — Adicionar o plugin na rota `mtdash-endpoints`:**
1. Menu lateral → **Routes** → abra `mtdash-endpoints`
2. Aba **Plugins** → **New Plugin** → escolha **Key Authentication**
3. **Key Names:** digite `X-API-Key` e pressione **Enter**
4. Clique em **Save**

**Passo 2 — Criar o Consumer:**
1. Menu lateral → **Consumers** → **New Consumer**
2. **Username:** `app-frontend` → **Save**

**Passo 3 — Criar a chave de acesso:**
1. Abra o consumer `app-frontend` → aba **Credentials** → **New Key Auth Credential**
2. **Key:** digite o valor desejado, ex: `minha-chave-123`, ou deixe **em branco** para gerar automaticamente
3. Clique em **Save** e copie o valor da chave gerada

### Usando a chave

```shell
$ curl http://localhost:8000/api/v1/taxa-mortalidade-infantil/ \
  -H "X-API-Key: minha-chave-123"
```

Ou no **Insomnia/Postman**:
- Header **Key:** `X-API-Key`
- Header **Value:** `minha-chave-123`

---

## 6. Adicionando autenticação JWT

### Via kong.yaml

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    routes:

      # Rota 1 — pública, sem autenticação
      - name: mtdash-docs
        paths:
          - /docs
          - /redoc
          - /openapi.json
        strip_path: false

      # Rota 2 — protegida, exige token JWT
      - name: mtdash-endpoints
        paths:
          - /api
        strip_path: false
        plugins:
          - name: jwt
            config:
              claims_to_verify:
                - exp

consumers:
  - username: usuario-jwt
    jwt_secrets:
      - key: meu-issuer
        secret: meu-segredo-jwt
```

### Via Admin API

```shell
# 1. Adicionar o plugin jwt na rota mtdash-endpoints
$ curl -X POST http://localhost:8001/routes/mtdash-endpoints/plugins \
  -d "name=jwt" \
  -d "config.claims_to_verify[]=exp"

# 2. Criar o consumer
$ curl -X POST http://localhost:8001/consumers \
  -d "username=usuario-jwt"

# 3. Criar o segredo JWT para o consumer
$ curl -X POST http://localhost:8001/consumers/usuario-jwt/jwt \
  -d "key=meu-issuer" \
  -d "secret=meu-segredo-jwt"
```

### Via Kong Manager

**Passo 1 — Adicionar o plugin na rota `mtdash-endpoints`:**
1. Menu lateral → **Routes** → abra `mtdash-endpoints`
2. Aba **Plugins** → **New Plugin** → escolha **JWT**
3. **Claims To Verify:** digite `exp` e pressione **Enter**
4. Clique em **Save**

**Passo 2 — Criar o Consumer:**
1. Menu lateral → **Consumers** → **New Consumer**
2. **Username:** `usuario-jwt` → **Save**

**Passo 3 — Criar o segredo JWT:**
1. Abra o consumer `usuario-jwt` → aba **Credentials** → **New JWT Credential**
2. Preencha:
   - **Key (issuer):** `meu-issuer`
   - **Secret:** `meu-segredo-jwt`
3. Clique em **Save**

### Usando o token

```shell
$ curl http://localhost:8000/api/v1/taxa-mortalidade-infantil/ \
  -H "Authorization: Bearer <seu-token-jwt>"
```

---

## 7. Adicionando CORS

Necessário quando o frontend (browser) acessa o Kong diretamente.

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    plugins:
      - name: cors
        config:
          origins:
            - "http://localhost:3000"
            - "https://meusite.gov.br"
          methods:
            - GET
            - POST
            - PUT
            - DELETE
            - OPTIONS
          headers:
            - Authorization
            - Content-Type
            - X-API-Key
          exposed_headers:
            - X-Auth-Token
          credentials: true
          max_age: 3600
    routes:
      - name: mtdash-rota
        paths:
          - /
        strip_path: false
```

---

## 8. Adicionando logs de requisições (file-log)

O plugin `file-log` grava um JSON por linha em um arquivo dentro do contêiner
a cada requisição recebida pelo Kong.

### Via kong.yaml

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    plugins:
      - name: file-log
        config:
          path: /tmp/kong-access.log
          reopen: true
    routes:
      - name: mtdash-rota
        paths:
          - /
        strip_path: false
```

### Via Admin API

```shell
# Adicionar o plugin file-log no serviço
$ curl -X POST http://localhost:8001/services/mtdash-api/plugins \
  -d "name=file-log" \
  -d "config.path=/tmp/kong-access.log" \
  -d "config.reopen=true"
```

### Via Kong Manager

1. Menu lateral → **Gateway Services** → abra `mtdash-api`
2. Aba **Plugins** → **New Plugin** → escolha **File Log**
3. Preencha:
   - **Path:** `/tmp/kong-access.log`
   - **Reopen:** ativado
4. Clique em **Save**

### Visualizando os logs

O arquivo fica dentro do contêiner Kong. Para visualizar:

```shell
# últimas 10 linhas
$ docker exec kong-kong-1 tail -n 10 /tmp/kong-access.log

# acompanhar em tempo real
$ docker exec kong-kong-1 tail -f /tmp/kong-access.log
```

Cada linha é um JSON com os seguintes campos principais:

| Campo | Descrição |
|-------|-----------|
| `client_ip` | IP do cliente |
| `request.method` | GET, POST, etc |
| `request.uri` | caminho acessado |
| `response.status` | código HTTP retornado |
| `upstream_status` | status retornado pela FastAPI |
| `latencies.request` | tempo total em ms |
| `latencies.proxy` | tempo da FastAPI em ms |

> O log fica dentro do contêiner e é perdido se o contêiner for removido.
> Para persistir, adicione um volume no `docker-compose.yml`:
>
> ```yaml
> volumes:
>   - ./logs/kong-access.log:/tmp/kong-access.log
> ```

---

## 9. Configuração completa recomendada

```yaml
_format_version: "2.1"
_transform: true

services:
  - name: mtdash-api
    url: http://mtdash-api.desenv.cge.mt.gov.br
    plugins:
      # aplicados em todas as rotas
      - name: rate-limiting
        config:
          minute: 60
          hour: 1000
          policy: local
      - name: cors
        config:
          origins:
            - "http://localhost:3000"
            - "https://meusite.gov.br"
          methods:
            - GET
            - POST
            - PUT
            - DELETE
            - OPTIONS
          headers:
            - Authorization
            - Content-Type
            - X-API-Key
          credentials: true
      - name: file-log
        config:
          path: /tmp/kong-access.log
    routes:

      # Rota 1 — pública, sem autenticação
      - name: mtdash-docs
        paths:
          - /docs
          - /redoc
          - /openapi.json
        strip_path: false

      # Rota 2 — protegida, exige X-API-Key
      - name: mtdash-endpoints
        paths:
          - /api
        strip_path: false
        plugins:
          - name: key-auth
            config:
              key_names:
                - X-API-Key

consumers:
  - username: app-frontend
    keyauth_credentials:
      - key: minha-chave-secreta-123
```

---

## 10. Configurando pelo Kong Manager (interface web)

> **Atenção:** o Kong Manager só está disponível na versão **Enterprise** do Kong.
> Na versão gratuita (OSS) a porta `8002` não serve nenhuma interface.

O Kong Manager gerencia 4 tipos de objetos independentes. Cada um é criado separadamente:

```
1. Serviço  →  define para onde o Kong encaminha as requisições
2. Rota 1   →  define quais caminhos são públicos (sem autenticação)
3. Rota 2   →  define quais caminhos são protegidos (com autenticação)
4. Consumer →  define quem pode acessar os endpoints protegidos
```

---

### 10.1 Criando o Serviço

O serviço representa a API de destino.

1. Acesse `http://localhost:8002`
2. Menu lateral → **Gateway Services** → **New Gateway Service**
3. Preencha:
   - **Name:** `mtdash-api`
   - **URL:** `http://mtdash-api.desenv.cge.mt.gov.br`
4. Clique em **Save**

---

### 10.2 Criando a Rota Pública (docs)

Esta rota expõe o Swagger sem exigir autenticação.
É um objeto separado da Rota 2 — **não é a mesma rota**.

1. Menu lateral → **Routes** → **New Route**
2. Preencha:
   - **Name:** `mtdash-docs`
   - **Service:** selecione `mtdash-api`
   - **Paths:** digite `/docs` e pressione **Enter** → digite `/redoc` e pressione **Enter** → digite `/openapi.json` e pressione **Enter**
     > Cada path deve virar um chip separado. Não separe por vírgula.
   - **Strip Path:** **desativado**
3. Clique em **Save**
4. **Não adicione nenhum plugin** nesta rota

Teste: `http://localhost:8000/docs` deve abrir o Swagger sem pedir chave.

---

### 10.3 Criando a Rota Protegida (endpoints da API)

Esta rota expõe os endpoints da API e exige autenticação.
É um objeto completamente separado da Rota 1 — **não é a mesma rota**.

1. Menu lateral → **Routes** → **New Route**
2. Preencha:
   - **Name:** `mtdash-endpoints`
   - **Service:** selecione `mtdash-api`
   - **Paths:** digite `/api` e pressione **Enter**
   - **Strip Path:** **desativado**
3. Clique em **Save**

Agora adicione o plugin de autenticação **nesta rota**:

4. Abra a rota `mtdash-endpoints` → aba **Plugins** → **New Plugin**
5. Escolha **Key Authentication**
6. Preencha:
   - **Key Names:** digite `X-API-Key` e pressione **Enter**
7. Clique em **Save**

> O plugin está na **rota** `mtdash-endpoints`, não no serviço.
> Isso garante que `/docs` continue público e só `/api/v1/...` exija autenticação.

---

### 10.4 Criando o Consumer e a Chave de Acesso

O consumer representa quem vai consumir a API. A chave é a senha de acesso.

1. Menu lateral → **Consumers** → **New Consumer**
2. Preencha:
   - **Username:** `app-frontend`
3. Clique em **Save**

Agora crie a chave de acesso para este consumer:

4. Abra o consumer `app-frontend` → aba **Credentials** → **New Key Auth Credential**
5. No campo **Key**:
   - Digite o valor que desejar, ex: `minha-chave-123`
   - Ou deixe **em branco** para o Kong gerar uma chave aleatória
6. Clique em **Save** e copie o valor da chave

Use a chave nas requisições:

```shell
$ curl http://localhost:8000/api/v1/taxa-mortalidade-infantil/ \
  -H "X-API-Key: minha-chave-123"
```

Ou no **Insomnia/Postman**:
- Header **Key:** `X-API-Key`
- Header **Value:** `minha-chave-123`

---

### 10.5 Adicionando o plugin file-log

1. Menu lateral → **Gateway Services** → abra `mtdash-api`
2. Aba **Plugins** → **New Plugin** → escolha **File Log**
3. Preencha:
   - **Path:** `/tmp/kong-access.log`
   - **Reopen:** ativado
4. Clique em **Save**

Para visualizar os logs:

```shell
# últimas 10 linhas
$ docker exec kong-kong-1 tail -n 10 /tmp/kong-access.log

# tempo real
$ docker exec kong-kong-1 tail -f /tmp/kong-access.log
```

---

### 10.6 Resumo do que foi criado

Ao final você terá os seguintes objetos no Kong Manager:

| Objeto | Nome | Finalidade |
|--------|------|-----------|
| Serviço | `mtdash-api` | aponta para a FastAPI |
| Rota | `mtdash-docs` | `/docs`, `/redoc`, `/openapi.json` — pública |
| Rota | `mtdash-endpoints` | `/api` — protegida com `key-auth` |
| Consumer | `app-frontend` | usuário com chave de acesso |

---

## 11. Verificando a configuração via Admin API

```shell
# listar todos os serviços
$ curl http://localhost:8001/services

# listar todas as rotas
$ curl http://localhost:8001/routes

# listar todos os plugins ativos
$ curl http://localhost:8001/plugins

# listar consumers
$ curl http://localhost:8001/consumers

# verificar saúde do Kong
$ curl http://localhost:8001/status
```

---

## 12. Referência rápida de plugins disponíveis

| Plugin | Finalidade |
|--------|-----------|
| `rate-limiting` | Limita requisições por tempo |
| `key-auth` | Autenticação por API Key |
| `jwt` | Autenticação por token JWT |
| `oauth2` | Autenticação OAuth 2.0 |
| `cors` | Controle de origens cross-origin |
| `ip-restriction` | Bloqueia/permite IPs específicos |
| `request-size-limiting` | Limita tamanho do body |
| `response-transformer` | Modifica headers/body da resposta |
| `file-log` | Log em arquivo |
| `http-log` | Log via HTTP para serviço externo |
| `prometheus` | Métricas para Prometheus/Grafana |

Documentação completa dos plugins: https://docs.konghq.com/hub/
