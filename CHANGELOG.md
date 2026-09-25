# Changelog

Todas as mudanças relevantes do Dockd são documentadas neste arquivo.

## [0.3.0] Não lançada

### Alterado

- Camada web reescrita a partir do design system aprovado em 25/09/2026: Biblioteca como home, página do Jogo com um único controle de status, Descobrir sobre o IGDB inteiro e Comprar como fila de lançamentos.
- Um status derivado por jogo (Quero, Backlog, Jogando, Zerado, Larguei), calculado de posse e estado de jogo, sem campo novo no modelo.
- Busca no IGDB filtrada por plataforma na própria consulta, para não devolver versões sem lançamento Nintendo.
- Importação do IGDB movida do controller para o contexto `Catalog`.
- Tipografia Archivo variável auto-hospedada no lugar de Noto Sans e JetBrains Mono.

### Removido

- DaisyUI, o seletor de tema, a barra lateral, o feature flag `flows` e as telas de Planejador, Carteira e Catálogo.

## [0.2.0] 2026-09-22

### Adicionado

- Telas refeitas no formato de biblioteca de mídia, sem slogans, subtítulos e cartões genéricos.
- Administração do catálogo somente pela API.
- Sincronização do catálogo com o IGDB.
- Crédito ao IGDB no rodapé.
- Variáveis do IGDB no compose do lab.
- Títulos de página.
- Dependências atualizadas (Phoenix 1.8.14, LiveView 1.2.12, DaisyUI 5.7.42, mint 1.10.1 com correção de segurança).

## [0.1.0] 2026-09-14

### Adicionado

- Planejador financeiro com calendário de lançamentos e pressão do backlog.
- Biblioteca com intenção, estado, filtros e posse independente.
- Catálogo e detalhe de jogos com preços, compras e vetos por versão.
- Carteira com saldo e reservas do eShop.
- API `/api/v1` e especificação OpenAPI em `/api/openapi`.
- Seeds demonstrativas idempotentes para desenvolvimento local.
- Temas claro e escuro e layout responsivo para telas pequenas e grandes.
