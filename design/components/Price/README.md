# Price
Um preço observado pelo usuário, com a data em que foi visto: valor em `t-num` e `visto em dd/mm/aaaa` em `t-meta`. Com mais de 30 dias, a data fica em `warn` e ganha a palavra desatualizado. Sem observação, mostra `Sem preço` em `ink-muted` e nada mais.

Nunca apresente um preço sem data e nunca o chame de preço atual. Alinha à direita, tabular. O consumidor fornece centavos, moeda e data da observação; a regra dos 30 dias é do componente.
