# Tabs
Filtro de status no topo da Biblioteca: Todos, Jogando, Backlog, Zerados, Quero. Todos é o que a conta tem; Quero, a lista de desejos, vem por último e não entra em Todos. Texto `ink-muted`, a aba ativa em `ink` com 2px de `red` na base sobre o fio `line`. A contagem em `t-meta` tabular fica ao lado do rótulo.

As abas são links com `aria-selected`, rolam horizontalmente no celular e nunca quebram linha. O consumidor fornece a lista com rótulo, contagem e destino. Uma aba com zero itens continua visível com sua contagem: some só a que não existe no modelo.
