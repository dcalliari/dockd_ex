# StatusChip
Um dos cinco estados de um jogo, em `t-label`, e a única forma em que um estado aparece na interface. Cinco preenchimentos: `gold` com `on-gold` para Quero, `ink` com `on-ink` para Backlog, `red` com `on-red` para Jogando, `surface-sunken` com `ink` para Zerado, `line-strong` com `surface` para Larguei. Zerado e Larguei ficam a 75% de opacidade e, sobre a capa, apagam a arte a 55% (`.dk-poster--faded`), como o Letterboxd faz com o que já foi visto. Sem borda, sem ícone.

Tamanho padrão de 22px em linhas e no StatusControl; `sm` de 18px sobre a capa, no canto superior esquerdo. O consumidor fornece só o `status`. Não crie um sexto estado nem um chip para plataforma ou mídia. A nota de contraste do texto branco sobre `gold` está no token.
