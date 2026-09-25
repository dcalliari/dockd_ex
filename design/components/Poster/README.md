# Poster
A capa do jogo em 3:4, o elemento principal de toda listagem e da página do jogo. Sempre `cover-ratio`; `radius-md` na grade e na página do jogo; `radius-sm` na miniatura de 33 por 44 dentro de linhas, que tem `thumb-height`. Fio interno `poster-edge`; em hover, quando é link, 2px de `red` por dentro.

O consumidor fornece `title` e, se houver, `cover_url` vindo do IGDB. Sem imagem, o Poster é `surface-sunken` com o título em `t-meta` no canto inferior esquerdo: nunca gradiente, nunca iniciais, nunca ícone. Um `status` opcional coloca um StatusChip pequeno no canto superior esquerdo; a miniatura nunca recebe chip.

Faça: use o mesmo Poster em Biblioteca, Descobrir, Comprar e na página do jogo. Não faça: recortar em quadrado, arredondar mais que `radius-md`, colocar texto sobre a arte além do chip.
