# Dockd

> Biblioteca, backlog e planejador de compras para jogos Nintendo Switch e Switch 2.

[![Elixir](https://img.shields.io/badge/Elixir-1.17%2B-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/) [![Phoenix](https://img.shields.io/badge/Phoenix-1.8.13-FD4F00?logo=phoenixframework&logoColor=white)](https://www.phoenixframework.org/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Dockd parte de uma ideia simples: o problema não é ter mais uma lista de jogos. É decidir **o que comprar, quando comprar e por quê**. O planejador é o centro do produto; biblioteca e backlog existem para dar contexto financeiro e de calendário a essa decisão. Jogos parados também precisam aparecer como um argumento honesto contra a próxima compra.

## O que é o Dockd

Um projeto pessoal, de escopo deliberadamente Nintendo, para organizar o caminho entre uma obra que interessa e uma compra que faz sentido. O produto não tenta ser rede social, catálogo de avaliações, agregador de notas ou diário de jogo.

A restrição a Switch e Switch 2 é uma escolha de produto, não uma limitação acidental. Ela permite tratar problemas específicos do ecossistema, como exclusivos, jogos físicos com pouca redução de preço, game-key cards e saldo preso no eShop.

## Estado atual

### Disponível hoje: versão 0.3.0

Quatro telas, desenhadas a partir do design system em [`design/`](design/FONTE.md) e aprovadas em maquete antes de virarem código:

- **Biblioteca** em `/`: grade de capas com um status por jogo (Quero, Backlog, Jogando, Zerado, Larguei), derivado de posse e estado de jogo; abas com contagem, filtros de plataforma e mídia, busca e ordenação.
- **Jogo** em `/jogos/:id`: capa com plataformas e exclusividade, um único controle de status, versões com preço observado e datado, e o histórico das ações.
- **Descobrir** em `/descobrir`: busca no IGDB inteiro restrita a Switch e Switch 2, com `Quero jogar` em um toque. Sem credenciais do IGDB, busca no catálogo local.
- **Comprar** em `/comprar`: a fila dos jogos em Quero, separada em próximos lançamentos, disponíveis e sem data, com reserva de saldo e registro de compra em linha.
- **Entrar** em `/entrar`: cada conta é uma biblioteca. Entra-se com e-mail e senha, e `Criar conta` abre uma conta nova sem convite. Com SMTP configurado, aparece também `Entrar por link`. Todas as telas acima exigem a conta.
- API JSON versionada em `/api/v1` e especificação em `/api/openapi`. Cada chamada leva `Authorization: Bearer <token>`, o token que `Copiar token da API`, no menu da conta, gera e copia; um novo substitui o anterior. O catálogo continua sendo administrado só pela API, por qualquer conta.
- Tema segue o sistema operacional; não há seletor de tema.
- Integração opcional com IGDB para sincronizar dados de jogos. O uso não comercial exige atribuição visível à fonte, presente no rodapé de toda página. No deploy por compose, as variáveis do IGDB são fornecidas pelo `.env`.

### Próximos passos

- Melhorar o recomendador com sinais históricos de uso.
- Cliente Flutter consumindo os contratos estáveis da API.
- Coleções e feedback explícito de recomendações permanecem fora do MVP.

## Modelo de domínio

A intenção pertence à obra. A versão é a unidade comprável e concentra plataforma, edição, disponibilidade, compra e preço. Posse e intenção são eixos independentes.

```mermaid
erDiagram
    GAMES ||--o{ RELEASES : possui
    GAMES ||--o{ ENTRIES : recebe
    RELEASES ||--o{ OWNERSHIPS : representa
    RELEASES ||--o{ PURCHASES : registra
    RELEASES ||--o{ PRICE_OBSERVATIONS : observa
    GAMES ||--o{ EVENTS : origina
    RELEASES ||--o{ EVENTS : referencia

    GAMES {
      uuid id PK
      string title
      string availability
      string pace
      string play_mode
    }
    RELEASES {
      uuid id PK
      uuid game_id FK
      string platform
      string edition
      date release_date
    }
    ENTRIES {
      uuid id PK
      uuid game_id FK
      string purchase_intent
      string play_state
      string backlog
    }
    OWNERSHIPS {
      uuid id PK
      uuid release_id FK
      string ownership_type
    }
    PURCHASES {
      uuid id PK
      uuid release_id FK
      integer price_cents
      string currency
    }
    PRICE_OBSERVATIONS {
      uuid id PK
      uuid release_id FK
      integer price_cents
      datetime observed_at
    }
```

`entries`, `ownerships`, `purchases`, `price_observations` e `events` fazem parte do modelo alvo. No estado atual do código, a migração implementada cobre `games` e `releases`; as demais estruturas serão adicionadas junto às respectivas features.

## Arquitetura e stack

Uma aplicação Phoenix única serve a interface LiveView e a API JSON sobre a mesma camada de domínio. O banco é acessado por Ecto e PostgreSQL; não há um segundo backend para o futuro cliente Flutter.

| Componente | Versão | Papel |
| --- | --- | --- |
| Elixir | `~> 1.17` | Linguagem e runtime da aplicação |
| Phoenix | `1.8.13` | Framework web |
| Phoenix LiveView | `1.2.11` | Interface reativa |
| Ecto | `3.14.2` | Modelo e consultas |
| Ecto SQL | `3.14.0` | Integração SQL e migrações |
| Postgrex | `0.22.4` | Driver PostgreSQL |
| Bandit | `1.12.5` | Servidor HTTP |
| Tailwind | `0.5.1` | Instalador do Tailwind CSS 4; os tokens e as classes `dk-` vivem em `assets/css/app.css` |
| Archivo | variável, latino | Única família tipográfica, auto-hospedada em `priv/static/fonts` |

As versões efetivamente resolvidas estão em [`mix.lock`](mix.lock); as restrições de dependência estão em [`mix.exs`](mix.exs).

## Começando

### Pré-requisitos

Para o caminho nativo, instale [mise](https://mise.jdx.dev/), que seleciona as versões definidas em [`.tool-versions`](.tool-versions), e tenha PostgreSQL disponível.

### Configuração local

A forma mais rápida, sem instalar Elixir ou PostgreSQL, é:

```bash
cp .env.example .env
docker compose up --build
```

Abra <http://localhost:4000>. Esse compose cria um PostgreSQL próprio e inicializa o banco junto com a aplicação. Os volumes podem ser removidos com `docker compose down -v`.

No caminho nativo:

```bash
cp .env.example .env
export DOCKD_DB_PASSWORD='sua-senha-local'
mix setup
mix phx.server
```

Para carregar o cenário de demonstração em um banco descartável, execute `mix run priv/repo/seeds.exs` e entre com `dono@dockd.local` e a senha `dockd-demonstracao`. O script pode ser executado novamente sem duplicar dados; nunca o use no banco do laboratório. Em desenvolvimento, o link de entrada chega em <http://localhost:4000/dev/mailbox>.

`mix setup` instala dependências, cria e migra o banco, instala os binários de assets e compila CSS e JavaScript. O [Makefile](Makefile) reúne atalhos para setup, desenvolvimento, testes, lint, formatação, banco e Docker.

Para usar um proxy reverso, copie `.env.example`, preencha `PHX_HOST`, `DATABASE_URL`, `SECRET_KEY_BASE`, `TRAEFIK_NETWORK` e `TRAEFIK_ENTRYPOINT`, e execute `docker compose -f compose.traefik.yml up --build`. Esse compose não cria a rede externa: ela deve existir no ambiente escolhido. O serviço reinicia automaticamente após reinicializações do host ou do Docker.

Em produção, `DATABASE_URL` e `SECRET_KEY_BASE` são obrigatórios. `PORT`, `PHX_HOST`, `POOL_SIZE` e `ECTO_IPV6` também são lidos em runtime. No compose Traefik, `IGDB_CLIENT_ID` e `IGDB_CLIENT_SECRET` habilitam a integração; `IGDB_SYNC_INTERVAL_MS` e `IGDB_SYNC_INITIAL_DELAY_MS` são opcionais e usam 86400000 ms e 1000 ms, respectivamente. Migrações de release podem ser executadas com `bin/migrate` dentro da imagem.

Contas em produção:

- A biblioteca anterior às contas não tem e-mail nem senha. Depois da migração, dê a ela uma entrada uma única vez: `bin/dockd eval 'Dockd.Release.claim_owner("email", "senha")'`. Até lá, ninguém entra nela; quem criar conta começa com uma biblioteca vazia.
- Senha esquecida sem SMTP: `bin/dockd eval 'Dockd.Release.reset_password("email", "senha")'`, que também encerra as sessões da conta.
- O envio de e-mail vem só da configuração: `SMTP_HOST`, `SMTP_PORT` (587 por padrão; 465 usa TLS direto), `SMTP_USERNAME`, `SMTP_PASSWORD` e `SMTP_FROM`. Sem `SMTP_HOST`, a tela Entrar oferece só e-mail e senha. O primeiro link usado por uma conta confirma o e-mail e descarta a senha criada antes dele, porque criar conta não verifica o e-mail.

### Testes e validações

```bash
mix test
mix precommit
```

`mix precommit` compila com warnings tratados como erro, verifica formatação, executa Credo em modo estrito e roda os testes.

## Roadmap

1. **0.1.0**: catálogo, biblioteca, compras, carteira, planejador e API entregues.
2. **Sinais de uso**: usar o log para orientar o próximo jogo.
3. **Cliente futuro**: consumir a API com Flutter após estabilizar os contratos.

Coleções, feedback explícito de recomendações e histórico completo de preços por loja estão fora do MVP atual.

## Decisões de produto e engenharia

- **Biblioteca primeiro**: a home é a biblioteca com um status por jogo. O planejador financeiro fica no domínio e na API e volta à tela quando houver compras registradas (decisão de 25/09/2026, que substitui a ADR-0007 na interface).
- **Design system antes de código**: toda tela nasce de uma maquete aprovada e emite só as classes de `design/components/bundle.css`.
- **Nintendo apenas**: Switch e Switch 2 concentram a complexidade que o Dockd quer resolver.
- **Obra diferente de versão**: vontade pertence ao jogo; posse, preço e compra pertencem à release.
- **Intenção diferente de posse**: querer jogar e já ter acesso são fatos independentes.
- **Estado atual mais log**: a entrada guarda o estado atual; o log append-only fornece sinais temporais. O log não é uma fonte para reconstruir o sistema.
- **Preço é observação**: valores são informados pelo usuário, datados e identificados por origem; nunca são apresentados como atuais sem contexto.
- **Catálogo com fatos**: duração, ritmo e modo de jogo são etiquetas preenchidas no cadastro da obra.
- **Uma aplicação**: Phoenix, LiveView, Ecto e PostgreSQL mantêm interface e API no mesmo domínio.
- **API preparada para o futuro**: a API JSON será consumida por um cliente Flutter, com testes de contrato por rota e OpenAPI gerada a partir do código.

## Licença

O Dockd é distribuído sob a licença [MIT](LICENSE).
