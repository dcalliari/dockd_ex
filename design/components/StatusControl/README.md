# StatusControl
O único controle da página do jogo. O StatusChip atual é o botão, sem borda nem seta; ao lado dele, em `t-meta`, desde quando (`desde 22/09/2026`). Ao passar o mouse, focar ou tocar, a data some e os outros quatro estados aparecem no mesmo lugar, esmaecidos a 55%, cada um inteiro ao passar por cima. Escolher grava na hora, o chip troca e a faixa fecha. Não há Salvar nem aviso de sucesso.

O consumidor fornece o status atual, a data e recebe o novo. O recuo da faixa é a largura do chip atual mais `space-2`, medida em runtime e escrita em `--dk-tray-offset`. Escolher Backlog num jogo sem posse registrada pergunta a mídia, Físico ou Digital, antes de gravar; Quero não é oferecido num jogo com posse.
