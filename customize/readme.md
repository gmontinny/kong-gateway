# Personalize o Kong injetando plugins e templates

Este dockerfile pega uma imagem Kong existente e adiciona plugins personalizados
e/ou um arquivo de template personalizado a ela.

```
docker build \
   --build-arg KONG_BASE="kong:0.14.1-ubuntu" \
   --build-arg PLUGINS="kong-http-to-https,kong-upstream-jwt" \
   --build-arg TEMPLATE="/mykong/nginx.conf" \
   --build-arg "KONG_LICENSE_DATA=$KONG_LICENSE_DATA" \
   --tag "sua_nova_imagem" .
```

O comando acima pegará a imagem `kong:0.14.1-alpine` e adicionará os plugins
(conhecidos em [luarocks.org](https://luarocks.org)) `kong-http-to-https` e
`kong-upstream-jwt` a ela. Também o template personalizado ([para renderizar o
arquivo de configuração nginx subjacente](https://docs.konghq.com/latest/configuration/#custom-nginx-templates--embedding-kong)
), localizado em `/mykong/nginx.conf`, será injetado.
A nova imagem resultante será marcada como `sua_nova_imagem`.

Ao iniciar um contêiner a partir da imagem recém-criada, os plugins e o
template adicionados serão aplicados automaticamente. Portanto, não é necessário especificar a
variável de ambiente `KONG_PLUGINS` nem o argumento de linha de comando `--nginx-conf`
para habilitá-los.

# Verificando os plugins disponíveis

Para verificar os plugins disponíveis em uma imagem, use o script de exemplo
[`list_plugins.sh`](list_plugins.sh).

# Lista curada de plugins

Esta ferramenta é baseada no gerenciador de pacotes LuaRocks para incluir todas as dependências
dos plugins. A variável `ROCKS_DIR` permite usar apenas uma lista curada de
rocks (em vez dos públicos).

Ela gerará um servidor LuaRocks local e não permitirá o uso de servidores públicos.
Para um exemplo de como usá-la, consulte o script [`example.sh`](example.sh).

## Argumentos:

 - `KONG_BASE` a imagem base a ser usada, padrão é `kong:latest`.
 - `PLUGINS` uma lista separada por vírgulas dos nomes dos plugins (NÃO arquivos rock!) que você deseja adicionar à imagem. Todas as
   dependências também serão instaladas.
 - `ROCKS_DIR` um diretório local onde os plugins/rocks permitidos estão localizados. Se
   especificado, apenas rocks deste local poderão ser instalados. Se
   não especificado, o servidor público `luarocks.org` será usado.
 - `TEMPLATE` o template de configuração personalizado a ser usado.
 - `KONG_LICENSE_DATA` necessário quando a imagem base é uma versão Enterprise
   do Kong.

Note que as entradas de `PLUGINS` são simplesmente comandos LuaRocks usados como:
`luarocks install <entrada>`. Portanto, qualquer coisa que o LuaRocks aceite pode ser adicionada
ali, incluindo opções de linha de comando. Por exemplo:

```
--build-arg PLUGINS="luassert --deps-mode=none"
```

Adicionará o módulo `luassert`, sem resolver dependências (isso é inútil,
mas demonstra como funciona).


## Limitações

- Por enquanto, funciona apenas para módulos Lua puros.
