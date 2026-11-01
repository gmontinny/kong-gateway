# Kong API Gateway

Kong Gateway gerenciado via Docker Compose, com suporte a múltiplos ambientes (local, desenvolvimento e homologação), deploy via **Portainer** e pipeline de build no **GitLab CI**.

> **Nota**
> Os arquivos Docker Compose usam o schema v3.9, requerendo Docker Engine 20.10.0+.

## O que é o Kong?

Kong é um API Gateway cloud-native, agnóstico de plataforma e escalável, reconhecido pelo alto desempenho e extensibilidade via plugins.

- Documentação oficial: [docs.konghq.com][kong-docs-url]
- Imagem Docker: [Docker Hub][kong-docker-url]

---

## Estrutura do projeto

```
project-kong/
├── config/
│   ├── kong.yaml          # Configuração declarativa — ambiente local
│   ├── kong.dev.yaml      # Configuração declarativa — desenvolvimento
│   └── kong.hml.yaml      # Configuração declarativa — homologação
├── .env.example           # Referência de variáveis (sem credenciais)
├── .gitlab-ci.yml         # Pipeline GitLab — build e push da imagem
├── docker-compose.yml     # Ambiente local (Postgres embutido)
├── docker-compose-dev.yml # Ambiente desenvolvimento (Portainer)
├── docker-compose-hml.yml # Ambiente homologação (Portainer)
├── portainer.env.dev      # Referência de variáveis para o Portainer DEV *
├── portainer.env.hml      # Referência de variáveis para o Portainer HML *
└── TUTORIAL_FASTAPI.md
```

> \* Arquivos ignorados pelo `.gitignore`. Nunca versionar com credenciais reais.

---

## Ambientes

### Local

Sobe o Kong com Postgres local. Indicado apenas para desenvolvimento e testes.

```shell
docker compose up -d
```

Contêineres iniciados na ordem correta:

| Contêiner              | Imagem        | Descrição                          |
|------------------------|---------------|------------------------------------|
| `db`                   | postgres:13   | Banco de dados local               |
| `kong-migrations`      | kong:latest   | Cria as tabelas na primeira execução |
| `kong-migrations-up`   | kong:latest   | Atualiza o schema em novas versões |
| `kong`                 | kong:latest   | O gateway em si                    |

### Desenvolvimento e Homologação

Nesses ambientes o banco **já existe externamente** (PostgreSQL em `portainer.desenv.cge.mt.gov.br:5433`).
O deploy é gerenciado pelo **Portainer** de cada ambiente, que puxa o `docker-compose` diretamente do GitLab.

Contêineres iniciados:

| Contêiner            | Descrição                            |
|----------------------|--------------------------------------|
| `kong-migrations`    | Cria as tabelas na primeira execução |
| `kong-migrations-up` | Atualiza o schema em novas versões   |
| `kong`               | O gateway em si                      |

---

## Portas expostas

| Porta  | Descrição                              |
|--------|----------------------------------------|
| `8000` | Proxy HTTP — onde suas rotas respondem |
| `8443` | Proxy HTTPS                            |
| `8001` | Admin API — gerenciamento via REST     |
| `8444` | Admin API HTTPS                        |
| `8002` | Kong Manager (interface web)           |

---

## Variáveis de ambiente

Todas as variáveis são injetadas pelo Portainer nos ambientes de dev e hml. Use os arquivos abaixo como referência ao cadastrá-las:

- `portainer.env.dev` — variáveis do ambiente de desenvolvimento
- `portainer.env.hml` — variáveis do ambiente de homologação

| Variável             | Descrição                              |
|----------------------|----------------------------------------|
| `TZ`                 | Timezone (ex: `America/Cuiaba`)        |
| `KONG_DOCKER_TAG`    | Tag da imagem Kong base                |
| `KONG_PG_HOST`       | Host do banco PostgreSQL externo       |
| `KONG_PG_PORT`       | Porta do banco PostgreSQL externo      |
| `KONG_PG_DATABASE`   | Nome do banco                          |
| `KONG_PG_USER`       | Usuário do banco                       |
| `KONG_PG_PASSWORD`   | Senha do banco                         |
| `REGISTRY_HOST`      | Host do registry Docker                |
| `IMG_NAME`           | Nome da imagem                         |
| `IMG_TAG`            | Tag da imagem                          |
| `KONG_PROXY_PORT`    | Porta do proxy HTTP (padrão `8000`)    |
| `KONG_PROXY_SSL_PORT`| Porta do proxy HTTPS (padrão `8443`)   |
| `KONG_ADMIN_PORT`    | Porta da Admin API (padrão `8001`)     |
| `KONG_ADMIN_SSL_PORT`| Porta da Admin API HTTPS (padrão `8444`) |
| `KONG_MANAGER_PORT`  | Porta do Kong Manager (padrão `8002`)  |
| `NODE_PLACEMENT`     | Label do nó Swarm para o deploy        |

---

## Pipeline GitLab CI

O `.gitlab-ci.yml` é responsável apenas pelo **build e push da imagem** no registry de cada ambiente. O deploy é feito pelo Portainer.

| Stage       | Trigger | Descrição                                      |
|-------------|---------|------------------------------------------------|
| `build-dev` | Manual  | Build e push no registry de desenvolvimento   |
| `build-hml` | Manual  | Build e push no registry de homologação        |

Variáveis necessárias em **GitLab → Settings → CI/CD → Variables**:

| Variável           | Descrição                        |
|--------------------|----------------------------------|
| `REGISTRY_HOST_DEV`| Host do registry de dev          |
| `REGISTRY_HOST_HML`| Host do registry de hml          |
| `USR_REGISTRY`     | Usuário do registry              |
| `PW_REGISTRY`      | Senha do registry                |

---

## Deploy via Portainer

1. Acesse o Portainer do ambiente desejado
2. Vá em **Stacks → Add stack**
3. Selecione **Repository** e informe:
   - URL do repositório GitLab
   - Compose file: `docker-compose-dev.yml` ou `docker-compose-hml.yml`
4. Na seção **Environment variables**, cadastre as variáveis do `portainer.env.dev` ou `portainer.env.hml`
5. Clique em **Deploy the stack**

---

## Configurando serviços e rotas

Ao acessar `http://<host>:8000/` sem nenhuma rota configurada, o Kong retornará:

```json
{ "message": "no Route matched with those values" }
```

Isso é esperado. Configure serviços e rotas pelo **Kong Manager** (`porta 8002`), pela **Admin API** (`porta 8001`) ou via `kong.yaml` em `config/`.

Consulte o [Tutorial FastAPI](./TUTORIAL_FASTAPI.md) para exemplos completos.

---

## Tutoriais

- [Gerenciando uma API FastAPI com o Kong](./TUTORIAL_FASTAPI.md) — proxy, rate limiting, autenticação por API Key, JWT, CORS e logs.

[kong-docs-url]: https://docs.konghq.com/
[kong-docker-url]: https://hub.docker.com/_/kong
