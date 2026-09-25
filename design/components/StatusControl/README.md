# StatusControl
O único controle da página do jogo: um botão de `control-height` que mostra o StatusChip atual e um chevron, e abre um menu com os cinco estados, cada um como o mesmo chip seguido do nome por extenso. Escolher grava na hora, o menu fecha e o botão mostra o chip novo. Não há Salvar nem aviso de sucesso.

Abaixo de 768px o menu é um `select` nativo com as cinco opções, e o botão continua igual. O consumidor fornece o status atual e recebe o novo. Escolher Backlog num jogo sem posse registrada pergunta a mídia, Físico ou Digital, antes de gravar; escolher Quero num jogo com posse não é oferecido.
