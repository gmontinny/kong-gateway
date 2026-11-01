# Kong API Gateway em Ambientes Corporativos: Arquitetura, Containerização e Pipeline CI/CD com Docker, GitLab e Portainer

**Área:** Ciência da Computação · Engenharia da Computação · Sistemas de Informação  
**Nível:** Intermediário / Avançado  
**Repositório:** https://github.com/gmontinny/kong

---

## Resumo

Este artigo apresenta a implementação de um API Gateway corporativo baseado no Kong Gateway, containerizado com Docker e orquestrado via Docker Swarm, com pipeline de integração contínua no GitLab CI e deploy gerenciado pelo Portainer. O projeto abrange três ambientes distintos (local, desenvolvimento e homologação), configuração declarativa via arquivos YAML, extensão da imagem base com plugins customizados em Lua, e aplicação de políticas de segurança como autenticação por API Key, JWT, rate limiting e CORS. O trabalho demonstra como padrões modernos de DevOps e arquitetura de microsserviços podem ser aplicados em contextos de governo digital e sistemas de informação corporativos.

**Palavras-chave:** API Gateway, Kong, Docker, DevOps, Microsserviços, CI/CD, GitLab, Portainer, Docker Swarm, Segurança de APIs.

---

## 1. Introdução

O crescimento acelerado de arquiteturas baseadas em microsserviços trouxe consigo um desafio fundamental: como gerenciar, proteger e monitorar dezenas ou centenas de APIs de forma centralizada, sem acoplamento entre os serviços? Nesse contexto, o conceito de **API Gateway** emergiu como um padrão arquitetural consolidado na indústria de software.

Um API Gateway atua como ponto de entrada único (*single entry point*) para todas as requisições de clientes externos, desempenhando funções transversais (*cross-cutting concerns*) como autenticação, autorização, rate limiting, logging, transformação de requisições e roteamento — funções que, sem um gateway, precisariam ser reimplementadas em cada microsserviço individualmente.

Este artigo documenta e analisa um projeto real de implantação do **Kong Gateway** em um ambiente corporativo de governo digital, publicado em https://github.com/gmontinny/kong. O projeto foi desenvolvido com foco em reprodutibilidade, segurança e separação de ambientes, utilizando um conjunto de tecnologias amplamente adotadas no mercado: Docker, Docker Compose, Docker Swarm, GitLab CI e Portainer.

---

## 2. Fundamentação Teórica

### 2.1 O Padrão API Gateway

Em arquiteturas de microsserviços, cada serviço expõe sua própria interface de comunicação. Sem um ponto de controle centralizado, os clientes precisariam conhecer os endereços individuais de cada serviço, lidar com diferentes mecanismos de autenticação e implementar lógica de retry e circuit breaking de forma distribuída.

O padrão API Gateway resolve esse problema ao introduzir uma camada intermediária que:

- Centraliza o roteamento de requisições
- Aplica políticas de segurança de forma uniforme
- Abstrai a topologia interna dos serviços
- Fornece observabilidade centralizada (logs, métricas, rastreamento)

### 2.2 Kong Gateway

O Kong é um API Gateway open-source, cloud-native, construído sobre o **OpenResty** (Nginx + LuaJIT). Sua arquitetura é baseada em plugins, o que permite estender suas funcionalidades sem modificar o núcleo do sistema. Os plugins são escritos em **Lua** e executados diretamente no loop de eventos do Nginx, garantindo altíssima performance.

Características técnicas relevantes:

- **Motor:** OpenResty (Nginx + LuaJIT)
- **Banco de dados:** PostgreSQL (modo tradicional) ou sem banco (modo DB-less/declarativo)
- **Extensibilidade:** plugins em Lua, com suporte a Go e JavaScript via PDK
- **Protocolo:** HTTP/1.1, HTTP/2, gRPC, WebSocket
- **Configuração:** imperativa via Admin API REST ou declarativa via arquivo YAML

### 2.3 Containerização e Orquestração

**Docker** é a plataforma de containerização que empacota a aplicação e suas dependências em uma unidade isolada e portável. **Docker Compose** define e executa aplicações multi-container a partir de um arquivo YAML. **Docker Swarm** é o orquestrador nativo do Docker para ambientes de produção em cluster, permitindo deploy distribuído, escalabilidade e alta disponibilidade.

### 2.4 CI/CD e GitOps

**Integração Contínua / Entrega Contínua (CI/CD)** é a prática de automatizar o build, teste e deploy de software a cada mudança no repositório. O **GitLab CI** executa pipelines definidos em `.gitlab-ci.yml`. O **Portainer** é uma interface de gerenciamento de containers que, integrado ao GitLab, implementa o padrão **GitOps**: o estado desejado da infraestrutura é declarado no repositório Git e aplicado automaticamente.

---

## 3. Arquitetura do Projeto

### 3.1 Visão Geral

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENTE                              │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP/HTTPS
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   KONG GATEWAY                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │rate-limit│  │ key-auth │  │   jwt    │  │   cors   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ file-log │  │ ip-restr │  │prometheus│                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
└──────────────────────────┬──────────────────────────────────┘
                           │ Proxy reverso
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              MICROSSERVIÇOS / APIs INTERNAS                 │
│         (FastAPI, Spring Boot, Node.js, etc.)               │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Estrutura de Arquivos

```
kong_proxy/
├── config/
│   ├── kong.yaml          # Configuração declarativa — local
│   ├── kong.dev.yaml      # Configuração declarativa — desenvolvimento
│   └── kong.hml.yaml      # Configuração declarativa — homologação
├── customize/
│   ├── Dockerfile         # Imagem customizada com plugins Lua
│   ├── packer.lua         # Script de empacotamento de plugins
│   └── list_plugins.sh    # Utilitário para listar plugins instalados
├── .env.example           # Referência de variáveis (sem credenciais)
├── .gitlab-ci.yml         # Pipeline GitLab — build e push
├── docker-compose.yml     # Ambiente local (Postgres embutido)
├── docker-compose-dev.yml # Ambiente desenvolvimento (Portainer/Swarm)
├── docker-compose-hml.yml # Ambiente homologação (Portainer/Swarm)
├── Dockerfile             # Imagem Kong com configuração declarativa
└── Makefile               # Atalhos para comandos frequentes
```

### 3.3 Separação de Ambientes

O projeto implementa três ambientes com características distintas:

| Aspecto | Local | Desenvolvimento | Homologação |
|---------|-------|-----------------|-------------|
| Banco de dados | PostgreSQL local (container) | PostgreSQL externo | PostgreSQL externo |
| Rede Docker | `kong-net` (interna) | `npm-public` (externa) | `traefik-public` (externa) |
| Orquestração | Docker Compose | Docker Swarm (Portainer) | Docker Swarm (Portainer) |
| Imagem Kong | `kong:latest` | Imagem customizada do registry | Imagem customizada do registry |
| Segredos | Docker Secrets (arquivo) | Variáveis de ambiente (Portainer) | Variáveis de ambiente (Portainer) |

---

## 4. Implementação Técnica

### 4.1 Ambiente Local — docker-compose.yml

O ambiente local é o mais completo em termos de segurança e boas práticas Docker, servindo como referência de implementação:

```yaml
x-kong-config:
  &kong-env
  KONG_DATABASE: postgres
  KONG_PG_DATABASE: kong
  KONG_PG_HOST: db
  KONG_PG_USER: kong
  KONG_PG_PASSWORD_FILE: /run/secrets/kong_postgres_password
```

**Pontos técnicos relevantes:**

**a) YAML Anchors (`&kong-env` / `<<: *kong-env`):** evita repetição de configurações comuns entre os serviços `kong-migrations`, `kong-migrations-up` e `kong`. É uma funcionalidade nativa do YAML que reduz a superfície de erro por inconsistência.

**b) Docker Secrets:** a senha do PostgreSQL é injetada via arquivo (`/run/secrets/kong_postgres_password`), nunca como variável de ambiente em texto plano. Isso evita que a credencial apareça em `docker inspect` ou em logs do sistema operacional.

**c) Volumes tmpfs:** os diretórios de runtime do Kong (`/var/run/kong` e `/tmp`) são montados como `tmpfs` (memória RAM), garantindo que dados temporários não sejam persistidos em disco e que o desempenho de I/O seja máximo.

**d) Filesystem read-only:** o container Kong é iniciado com `read_only: true`, impedindo que qualquer processo dentro do container escreva no sistema de arquivos da imagem. Isso reduz drasticamente a superfície de ataque em caso de comprometimento.

**e) `security_opt: no-new-privileges`:** impede que processos dentro do container elevem seus privilégios via `setuid`/`setgid`, uma camada adicional de hardening.

**f) Healthchecks encadeados:** o serviço `kong` só inicia após o banco de dados estar saudável (`service_healthy`) e as migrations terem sido concluídas com sucesso (`service_completed_successfully`). Isso garante a ordem correta de inicialização sem scripts de espera manuais.

**g) Migrations separadas:** dois serviços distintos gerenciam as migrations:
- `kong-migrations`: executa `bootstrap` (criação inicial do schema)
- `kong-migrations-up`: executa `up` + `finish` (atualizações de schema)

Essa separação permite que o `bootstrap` falhe silenciosamente em execuções subsequentes (o schema já existe), enquanto o `up` sempre verifica e aplica novas migrations.

### 4.2 Ambientes de Produção — docker-compose-dev.yml e docker-compose-hml.yml

Nos ambientes de desenvolvimento e homologação, o banco de dados é externo e gerenciado separadamente. As diferenças arquiteturais são:

**Rede externa:** os containers se conectam a redes Docker pré-existentes (`npm-public` para dev, `traefik-public` para hml), criadas e gerenciadas pelo Nginx Proxy Manager e Traefik respectivamente. Isso permite que o Kong seja exposto através de um reverse proxy com terminação SSL.

**Docker Swarm com placement constraints:**
```yaml
deploy:
  mode: global
  placement:
    constraints: [node.labels.cloud == worker03]
```

O modo `global` garante que exatamente uma instância do Kong rode em cada nó que satisfaça a constraint. A constraint `node.labels.cloud == worker03` direciona o deploy para um nó específico do cluster, permitindo controle fino sobre onde os workloads são executados.

**Política de restart com delay:**
```yaml
restart_policy:
  condition: on-failure
  delay: 600s
```

O delay de 600 segundos entre tentativas de restart evita loops de reinicialização rápidos (*crash loops*) que poderiam sobrecarregar o banco de dados com tentativas de conexão.

### 4.3 Dockerfile — Imagem Customizada

```dockerfile
ARG KONG_BASE=kong:latest
FROM ${KONG_BASE}

ARG PROFILE=dev
COPY config/kong.${PROFILE}.yaml /etc/kong/kong.yaml

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong-health

USER kong
```

Este Dockerfile implementa o padrão de **configuração como código**: a configuração declarativa do Kong é embutida diretamente na imagem Docker durante o build. O argumento `PROFILE` permite que a mesma instrução `docker build` gere imagens diferentes para cada ambiente, passando `--build-arg PROFILE=dev` ou `--build-arg PROFILE=hml`.

O `HEALTHCHECK` nativo do Docker garante que o orquestrador (Swarm/Compose) saiba quando o Kong está realmente pronto para receber tráfego, não apenas quando o processo iniciou.

### 4.4 Customização com Plugins Lua — customize/Dockerfile

O diretório `customize/` contém uma infraestrutura completa para construir imagens Kong com plugins Lua customizados instalados via **LuaRocks**:

```dockerfile
FROM ${KONG_BASE} AS build

ARG PLUGINS
COPY packer.lua /packer.lua
RUN /usr/local/openresty/luajit/bin/luajit /packer.lua -- "$INJECTED_PLUGINS"

FROM ${KONG_BASE}
COPY --from=build /usr/local/share/lua/5.1 /usr/local/share/lua/5.1
COPY --from=build /usr/local/lib/lua/5.1 /usr/local/lib/lua/5.1
COPY --from=build /usr/local/lib/luarocks/rocks-5.1 /usr/local/lib/luarocks/rocks-5.1
```

Este é um **multi-stage build**: o primeiro estágio (`build`) instala os plugins e suas dependências em um ambiente completo. O segundo estágio copia apenas os artefatos necessários (arquivos `.lua` e bibliotecas `.so`), descartando ferramentas de build. O resultado é uma imagem final menor e com menor superfície de ataque.

### 4.5 Pipeline GitLab CI — .gitlab-ci.yml

```yaml
stages:
  - build-dev
  - build-hml

build-dev:
  stage: build-dev
  environment:
    name: desenv
    url: http://kong.desenv.cge.mt.gov.br/
  when: manual
  script:
    - docker build -t $IMG_NAME:$IMG_TAG --build-arg PROFILE=dev .
    - docker image tag $IMG_NAME:$IMG_TAG $REGISTRY_HOST_DEV:5000/$IMG_NAME:$IMG_TAG
    - docker login $REGISTRY_HOST_DEV:5000 -u $USR_REGISTRY -p $PW_REGISTRY
    - docker image push $REGISTRY_HOST_DEV:5000/$IMG_NAME:$IMG_TAG
```

**Decisões de design do pipeline:**

- **Trigger manual (`when: manual`):** o deploy não é automático. Um humano precisa aprovar explicitamente o build para cada ambiente. Isso é uma prática de segurança importante em ambientes corporativos, especialmente para homologação.

- **Separação de stages:** `build-dev` e `build-hml` são stages independentes, permitindo promover uma versão para dev sem necessariamente promovê-la para hml.

- **Registry privado:** as imagens são publicadas em registries Docker privados (porta 5000), não no Docker Hub público. Isso mantém as imagens customizadas dentro do perímetro da organização.

- **Variáveis protegidas:** credenciais do registry (`USR_REGISTRY`, `PW_REGISTRY`) são armazenadas como variáveis protegidas no GitLab, nunca no código-fonte.

### 4.6 Configuração Declarativa — kong.yaml

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
      - name: cors
        config:
          origins:
            - "http://localhost:3000"
          methods: [GET, POST, PUT, DELETE, OPTIONS]
          headers: [Authorization, Content-Type, X-API-Key]
          credentials: true
    routes:
      - name: mtdash-rota
        paths:
          - /
        strip_path: false
```

O modo declarativo (DB-less) do Kong permite versionar toda a configuração do gateway no Git, tratando a infraestrutura como código (*Infrastructure as Code*). Qualquer mudança nas rotas, plugins ou consumers é rastreável, revisável e revertível.

---

## 5. Segurança de APIs — Plugins em Prática

### 5.1 Autenticação por API Key

```yaml
routes:
  - name: mtdash-endpoints
    paths: [/api]
    plugins:
      - name: key-auth
        config:
          key_names: [X-API-Key]

consumers:
  - username: app-frontend
    keyauth_credentials:
      - key: minha-chave-secreta-123
```

O plugin `key-auth` implementa autenticação estática por chave. A chave é enviada no header `X-API-Key`. O Kong valida a chave antes de encaminhar a requisição ao upstream, garantindo que apenas consumers cadastrados acessem os endpoints protegidos.

**Separação de rotas públicas e privadas:** uma decisão arquitetural importante do projeto é manter rotas separadas para endpoints públicos (documentação Swagger) e protegidos (endpoints da API). O plugin de autenticação é aplicado apenas na rota `/api`, mantendo `/docs`, `/redoc` e `/openapi.json` acessíveis sem autenticação.

### 5.2 Autenticação JWT

```yaml
plugins:
  - name: jwt
    config:
      claims_to_verify: [exp]

consumers:
  - username: usuario-jwt
    jwt_secrets:
      - key: meu-issuer
        secret: meu-segredo-jwt
```

O plugin `jwt` valida tokens JWT assinados com HMAC-SHA256. A claim `exp` é verificada automaticamente, rejeitando tokens expirados. O Kong extrai o `iss` (issuer) do token e busca o segredo correspondente no banco de dados para validar a assinatura.

### 5.3 Rate Limiting

```yaml
plugins:
  - name: rate-limiting
    config:
      minute: 60
      hour: 1000
      policy: local
```

O rate limiting protege os serviços upstream contra abuso, ataques de força bruta e picos de tráfego não intencionais. Quando o limite é atingido, o Kong retorna `HTTP 429 Too Many Requests` sem sequer encaminhar a requisição ao upstream, economizando recursos do serviço protegido.

A política `local` armazena os contadores em memória no próprio processo Kong. Para ambientes com múltiplas instâncias, a política `redis` permite compartilhar os contadores entre instâncias.

### 5.4 CORS

```yaml
plugins:
  - name: cors
    config:
      origins: ["http://localhost:3000", "https://meusite.gov.br"]
      methods: [GET, POST, PUT, DELETE, OPTIONS]
      headers: [Authorization, Content-Type, X-API-Key]
      credentials: true
      max_age: 3600
```

O plugin CORS gerencia os headers `Access-Control-Allow-*` de forma centralizada, eliminando a necessidade de configurar CORS em cada microsserviço individualmente. O `max_age: 3600` instrui o browser a cachear a resposta do preflight por 1 hora, reduzindo o número de requisições OPTIONS.

### 5.5 Logging Estruturado

```yaml
plugins:
  - name: file-log
    config:
      path: /tmp/kong-access.log
      reopen: true
```

O plugin `file-log` grava um JSON por linha para cada requisição, contendo: IP do cliente, método HTTP, URI, status da resposta, status do upstream e latências (total e do upstream). Esses logs podem ser consumidos por ferramentas como Filebeat, Fluentd ou Logstash para centralização em um SIEM ou stack ELK.

---

## 6. Análise de Pontos Positivos

### 6.1 Separação Clara de Responsabilidades

O projeto separa explicitamente três preocupações distintas:
1. **Infraestrutura de runtime** (docker-compose files)
2. **Configuração do gateway** (kong.yaml files)
3. **Pipeline de entrega** (.gitlab-ci.yml)

Essa separação facilita a manutenção, pois mudanças em rotas e plugins não exigem alterações nos arquivos de infraestrutura, e vice-versa.

### 6.2 Segurança por Padrão

O ambiente local implementa múltiplas camadas de hardening que vão além do mínimo necessário para funcionar:
- Filesystem read-only
- Docker Secrets para credenciais
- `no-new-privileges`
- Volumes tmpfs para dados temporários
- Usuário não-root (`USER kong`)

Essas práticas demonstram maturidade em segurança de containers e servem como referência para outros projetos.

### 6.3 Reprodutibilidade Total

Qualquer desenvolvedor com Docker instalado pode subir o ambiente completo com um único comando:
```shell
docker compose up -d
```

A configuração declarativa no `kong.yaml` garante que o estado do gateway seja idêntico em todas as execuções, eliminando o problema de "funciona na minha máquina".

### 6.4 Configuração como Código (CaC)

Toda a configuração do Kong — serviços, rotas, plugins, consumers — está versionada em arquivos YAML no repositório Git. Isso permite:
- Revisão de mudanças via Pull/Merge Requests
- Rollback imediato para qualquer versão anterior
- Auditoria completa de quem mudou o quê e quando
- Replicação do ambiente em novos clusters sem configuração manual

### 6.5 Pipeline Controlado e Seguro

O uso de triggers manuais no GitLab CI é uma decisão deliberada de segurança: nenhum deploy acontece automaticamente. Isso é especialmente importante em ambientes governamentais onde mudanças em produção precisam de aprovação explícita.

### 6.6 Extensibilidade via Plugins Lua

A infraestrutura de customização em `customize/` permite que a organização desenvolva e distribua plugins Kong proprietários, escritos em Lua, sem depender de plugins de terceiros ou da versão Enterprise do Kong. O multi-stage build garante que os plugins sejam compilados e empacotados de forma reprodutível.

### 6.7 Integração com Ecossistema de Observabilidade

O suporte nativo ao plugin `prometheus` permite integrar o Kong com Prometheus e Grafana para monitoramento em tempo real de:
- Taxa de requisições por rota
- Latência de upstream
- Taxa de erros (4xx, 5xx)
- Contadores de rate limiting

---

## 7. Casos de Uso e Aplicabilidade

### 7.1 Governo Digital

O projeto foi desenvolvido no contexto de um sistema de governo digital (CGE-MT), onde APIs de dados públicos precisam ser expostas com controle de acesso, rate limiting para evitar sobrecarga dos servidores e logging para auditoria. O Kong centraliza essas preocupações sem modificar as APIs subjacentes.

### 7.2 Arquitetura de Microsserviços

Em sistemas com múltiplos microsserviços, o Kong elimina a necessidade de implementar autenticação, rate limiting e CORS em cada serviço individualmente. Um novo microsserviço é adicionado ao gateway com a criação de um `service` e uma `route` no `kong.yaml`, sem nenhuma mudança no código do serviço.

### 7.3 Ambientes Multi-tenant

O modelo de `consumers` do Kong permite criar chaves de API individuais para cada cliente ou sistema que consome as APIs, com políticas de rate limiting diferenciadas por consumer. Isso é útil em cenários de API pública onde diferentes clientes têm diferentes cotas de uso.

### 7.4 Migração Gradual de Sistemas Legados

O Kong pode atuar como fachada (*facade*) na frente de sistemas legados, adicionando autenticação moderna (JWT, OAuth2) e observabilidade sem modificar o sistema legado. A rota no Kong aponta para o sistema legado, e os plugins adicionam as capacidades modernas na camada do gateway.

---

## 8. Limitações e Considerações

### 8.1 Kong Manager na Versão OSS

O Kong Manager (interface web na porta 8002) está disponível apenas na versão **Enterprise** do Kong. Na versão open-source (OSS), a administração é feita exclusivamente via Admin API REST ou arquivo `kong.yaml`. O projeto documenta explicitamente essa limitação no tutorial.

### 8.2 Rate Limiting com Política Local

A política `local` de rate limiting armazena contadores em memória no processo Kong. Em deployments com múltiplas réplicas (Docker Swarm com `replicas > 1`), cada instância mantém seus próprios contadores independentes, o que pode resultar em limites efetivos maiores que o configurado. Para ambientes com múltiplas instâncias, a migração para a política `redis` é necessária.

### 8.3 Segredos em Ambientes de Produção

Nos ambientes de dev e hml, as credenciais do banco de dados são injetadas como variáveis de ambiente pelo Portainer. Embora seja uma prática comum, variáveis de ambiente são visíveis via `docker inspect`. Para maior segurança, a migração para Docker Secrets ou um gerenciador de segredos dedicado (HashiCorp Vault, AWS Secrets Manager) seria recomendada.

---

## 9. Comparação com Alternativas

| Critério | Kong | Nginx | Traefik | AWS API Gateway |
|----------|------|-------|---------|-----------------|
| Plugins nativos | +200 | Limitado | Moderado | Limitado |
| Configuração declarativa | Sim | Sim | Sim | Sim |
| Interface de administração | Sim (Enterprise) | Não | Sim | Sim |
| Self-hosted | Sim | Sim | Sim | Não |
| Extensibilidade | Lua/Go/JS | C/Lua | Go | Não |
| Curva de aprendizado | Média | Alta | Baixa | Baixa |
| Custo | OSS gratuito | Gratuito | Gratuito | Pay-per-use |

O Kong se destaca pela riqueza de plugins nativos e pela extensibilidade via Lua, sendo a escolha natural para organizações que precisam de funcionalidades avançadas sem depender de soluções proprietárias de nuvem.

---

## 10. Conclusão

Este projeto demonstra como o Kong Gateway pode ser implantado de forma profissional em ambientes corporativos, combinando boas práticas de segurança de containers, configuração como código, pipeline de CI/CD controlado e separação clara de ambientes.

Do ponto de vista acadêmico, o projeto é um exemplo concreto da aplicação de múltiplos conceitos fundamentais de Engenharia de Software e Sistemas Distribuídos:

- **Padrão Proxy/Gateway** (GoF Structural Patterns)
- **Separação de preocupações** (Separation of Concerns)
- **Infraestrutura como Código** (IaC)
- **Entrega Contínua** (Continuous Delivery)
- **Princípio do menor privilégio** (Security Hardening)
- **Observabilidade** (Logging, Métricas)

Para estudantes e profissionais das áreas de Ciência da Computação, Engenharia da Computação e Sistemas de Informação, este projeto serve como referência prática de como tecnologias modernas de containerização e DevOps são aplicadas em sistemas reais de produção, especialmente no contexto de governo digital e arquiteturas de microsserviços.

O código-fonte completo, incluindo todos os arquivos de configuração, Dockerfiles e pipeline CI/CD, está disponível em: **https://github.com/gmontinny/kong**

---

## Referências

- KONG INC. *Kong Gateway Documentation*. Disponível em: https://docs.konghq.com/. Acesso em: 2025.
- RICHARDSON, C. *Microservices Patterns*. Manning Publications, 2018.
- NEWMAN, S. *Building Microservices*. 2. ed. O'Reilly Media, 2021.
- DOCKER INC. *Docker Documentation*. Disponível em: https://docs.docker.com/. Acesso em: 2025.
- FOWLER, M. *Patterns of Enterprise Application Architecture*. Addison-Wesley, 2002.
- OPENRESTY. *OpenResty — Fast Web App Server by Extending Nginx*. Disponível em: https://openresty.org/. Acesso em: 2025.
- GITLAB INC. *GitLab CI/CD Documentation*. Disponível em: https://docs.gitlab.com/ee/ci/. Acesso em: 2025.
- PORTAINER IO. *Portainer Documentation*. Disponível em: https://docs.portainer.io/. Acesso em: 2025.
- NIST. *NIST Special Publication 800-190: Application Container Security Guide*. National Institute of Standards and Technology, 2017.
