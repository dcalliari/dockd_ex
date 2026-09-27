# Price
Um preço observado pelo usuário, com a data em que foi visto: valor em `t-num` e `visto em dd/mm/aaaa` em `t-meta`. Com mais de 30 dias, a data fica em `warn` e ganha a palavra desatualizado. Sem observação, mostra `Sem preço` em `ink-muted` e nada mais.

Nunca apresente um preço sem data e nunca o chame de preço atual. Alinha à direita, tabular. O consumidor fornece centavos, moeda e data da observação; a regra dos 30 dias é do componente.

Para quem tem conta, em Comprar e na página do jogo, o preço é um botão: clicar abre o registro manual embaixo da linha, como a etiqueta abre o status, com fundo `surface-raised` no hover e enquanto aberto. A mesma forma mostra o valor pago depois de Comprei (`pago em dd/mm/aaaa`), que se clica para corrigir. Ver `maquetes/compra.html`.
