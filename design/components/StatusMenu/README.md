# StatusMenu
O único controle de status do sistema: sobre a capa na Biblioteca e em Descobrir, e no herói da página do jogo. O StatusChip atual é o botão. Com mouse, apontar para ele abre embaixo os outros estados, cada um como StatusChip num painel `surface-raised` com fio `line`; clicar nele desmarca o status, e o chip riscado ao apontar avisa isso. No toque não há apontar: o primeiro toque abre, o segundo toque na etiqueta desmarca, e tocar fora fecha. Pelo teclado, o foco abre e Enter desmarca.

Desmarcar é a única forma de tirar um jogo da biblioteca. Não existe lixeira, link "Tirar da biblioteca", confirmação, aviso nem faixa: o estado muda no lugar. Na grade o cartão fica onde estava, com `+ Adicionar`, até a aba ou o filtro mudar, e escolher de novo desfaz. Sai a entrada e a posse; compra, preço visto, saldo e histórico ficam, e o histórico ganha "Saiu da biblioteca".

Sem status, o chip é `+ Adicionar` e abre os cinco. Nunca se oferece o estado atual, e Quero não é oferecido num jogo com posse. Escolher Backlog num jogo sem posse troca os chips, no mesmo painel, pela pergunta "Tem em qual versão?" com uma linha por plataforma e mídia (`Switch 2 · Físico`) e Cancelar; escolher grava posse e status juntos, na edição padrão da plataforma. A edição exata (Deluxe, pacote) vem de Comprei, quando há compra. Para o visitante o chip é um link para Entrar que volta com o controle aberto.

Tamanhos: `sm` sobre a capa, no canto superior esquerdo, e `md` na página do jogo, com `desde dd/mm/aaaa` em `t-meta` ao lado. Sobre a capa o painel nunca passa da largura do cartão. Fechado, o painel não ocupa espaço, e nada estoura a tela em 375px.

O consumidor fornece o status atual, as opções (`Dockd.Library.status_options/1`), o identificador do jogo e, na página do jogo, a data. A regra de domínio fica em `Dockd.Library.set_status/4` e os eventos em `DockdWeb.GameEvents`, os mesmos em toda tela.
