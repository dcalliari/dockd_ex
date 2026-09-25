# History
O histórico de um jogo na página do jogo: trilho vertical com as ações do log, da mais recente à mais antiga. Cada item tem o verbo em negrito (`Começou a jogar`, `Viu o preço: R$ 350,00`, `Registrou a posse`, `Entrou na biblioteca`, `Comprou`, `Zerou`), o tempo relativo em `ink-muted` ao lado (`há 3 dias`) e, embaixo, data exata, versão e o que mais couber em `t-meta` separado por ponto mediano.

Dois marcadores quadrados de 9px no trilho: `red` na ação que definiu o estado atual do jogo, `ink` nas demais. Sem ícone por tipo de ação, sem agrupamento por mês, sem cor por tipo. O consumidor fornece a lista de eventos já traduzidos em verbo e o índice do evento corrente. Uma lista longa corta em dez itens com `Ver tudo` em `.dk-link`.
