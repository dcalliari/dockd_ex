# Design system do Dockd

Fonte de verdade navegável, com previews ao vivo e capas reais:
https://claude.ai/artifact/SWbSdyF7AX2Q7vgUGzy2by

Esta pasta é a cópia em arquivos, para agentes e para o build: `README.md` é o brand book,
`tokens.json` os tokens, `components/bundle.css` as classes `dk-` que os function components
Phoenix devem emitir, e `components/<Nome>/README.md` as regras de cada componente. Os previews
referenciam imagens no armazenamento do artefato (`/_blob/...`) e só renderizam lá.

Aprovado por Daniel em 25/09/2026. Mudança de token ou de regra acontece primeiro no artefato e
depois é copiada para cá, nunca o contrário.
