# SearchField
Campo de busca por título, com lupa à esquerda em `ink-muted`, borda de 1px em `line-strong` e altura `control-height`. Filtra ao digitar com debounce de 250ms; na Biblioteca busca a lista do usuário, em Descobrir busca o IGDB inteiro.

Sem rótulo visível: o placeholder diz o que buscar e o `aria-label` repete. O consumidor fornece `placeholder` e `value`. Nunca acompanhado de botão Buscar.
