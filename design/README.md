dockd. é uma biblioteca pessoal de jogos de Switch e Switch 2: o que tenho, o que quero, o que estou jogando e o que vou comprar. A interface segue a família Letterboxd e Backloggd: a capa é o conteúdo, o texto é metadado, e cada tela tem uma ação primária. Paleta vermelho, branco e preto, uma família tipográfica, dois temas.

## Sete regras de consistência

Valem antes de qualquer componente. Se uma tela as respeita, ela parece Dockd.

1. **Um estado é sempre um StatusChip.** Onde quer que o status de um jogo apareça, sobre a capa, numa linha, no seletor da página do jogo, ele tem a mesma forma e as mesmas palavras. Não existe versão em texto solto, em cor de fundo ou em ícone.
2. **Uma ação é sempre um Button.** Primário só uma vez por tela, vermelho. Dentro de linha e de cartão, só secundário pequeno. Um link em `red-ink` é navegação, não ação.
3. **Três preenchimentos sólidos: `red`, `ink` e `gold`.** `gold` existe só no chip Quero. Todo o resto é superfície, fio ou texto.
4. **Borda tem 1px e é `line-strong` quando é controle, `line` quando é separação.** Não existe 1,5px, não existe 2px, exceto o indicador de aba ativa.
5. **Número é tabular e alinhado à direita, com a data ao lado.** Dinheiro sem data não existe.
6. **Uma ação, um controle, um texto, um efeito.** Uma ação que aparece em mais de uma tela usa o mesmo componente, as mesmas palavras e grava o mesmo efeito em todas, e a regra de domínio fica num lugar só (`Dockd.Library`, `Dockd.Purchasing`), chamada por um só tratador de eventos (`DockdWeb.GameEvents`). Uma tela não ganha um atalho próprio para algo que outra tela já faz. O inventário está em `maquetes/status.html`.
7. **Nunca diálogo nativo do navegador.** Sem `confirm`, `alert`, `prompt` nem `data-confirm`. O que precisar de confirmação confirma dentro da interface, no próprio controle. `DockdWeb.NativeDialogTest` falha se algum aparecer em `lib/` ou `assets/js`.

## Texto

- Escreva em pt-BR, na voz de quem usa: **+ Adicionar**, **Comprei**, **Desfazer**, **Registrar preço**. O botão diz o que acontece; nunca "Salvar" ou "Confirmar".
- Nenhuma string de interface passa de seis palavras. Exceções: estado vazio, confirmação de ação irreversível e as três frases de Sobre.
- Sem slogan, subtítulo, eyebrow ou sermão. A navegação já diz onde a pessoa está; a tela não repete o nome em um título grande.
- Cada informação aparece uma vez por tela. Um valor padrão não é informação: um jogo sem preço observado não mostra "R$ 0,00" nem "Sem alvo", mostra `Sem preço` uma vez, em `ink-muted`.
- Preço nunca é "preço atual". É `t-num` com `visto em dd/mm/aaaa` em `t-meta`. Passados 30 dias, a data fica em `warn` com a palavra desatualizado.
- Datas em `dd/mm/aaaa`; mês abreviado em caixa alta sem ponto no bloco de data (`SET`, `OUT`). Dinheiro em `R$ 1.249,90`.
- Metadado separado por ponto mediano: `Switch 2 · 2026 · Team Cherry`. Nunca vírgula, nunca barra, nunca espaço duplo.
- Sem emoji, sem ponto de exclamação.
- O crédito da fonte (`Dados de jogos por IGDB`) aparece uma vez por tela, no Footer, e em nenhum outro lugar do corpo. A página do jogo leva só o link `Mais informações no IGDB`, em `t-meta` `ink-muted`, para a página daquele jogo. Entrar e Criar conta não têm Footer nem crédito.

## Cor

- A página é `surface`; o texto é `ink`; o metadado é `ink-muted`. Não existe um terceiro nível de cinza: se algo não merece `ink-muted`, não merece estar na tela.
- `red` é preenchimento em cinco lugares e só neles: o botão primário da tela, o chip Jogando, o indicador da aba e do destino ativos, o ponto do wordmark e o cartão de jogo de Switch 2 do ExclusiveMark. Como texto e contorno, use `red-ink`, que escurece no claro e clareia no escuro para manter contraste.
- Texto sobre `red` é `on-red`; sobre `ink` é `on-ink`. Nunca `#fff` literal.
- Os cinco status são preenchimentos: amarelo Quero, preto Backlog, vermelho Jogando, cinza claro Zerado, cinza escuro Larguei. Zerado e Larguei ficam a 75% e apagam a capa a 55%, como o Letterboxd faz com o que já foi visto. Ver StatusChip.
- `warn` tem um único uso: preço desatualizado. Não há verde de sucesso nem azul de informação. Uma ação bem-sucedida se mostra no próprio controle mudando de estado, não em um aviso.
- Cartão só quando delimita algo de verdade. Separe com espaço e com `line`.
- Foco de teclado: `focus-ring` em 2px sólidos, afastados 2px, em todo controle e link de capa.

## Tipografia

- Uma família: Archivo, variável em peso e largura, pelo Google Fonts. A largura faz o papel de uma segunda família: 125% no wordmark, 110% no `t-display`, 100% no corpo, 90% em `t-label` e `t-num-lg`.
- Nove estilos e nenhum fora deles. Título de jogo em cartão e linha é `t-heading`; tudo que se clica é `t-control`; tudo que descreve é `t-meta`; tudo que é caixa alta é `t-label`; dinheiro e data são `t-num`.
- Título de seção é SectionHead, em `t-label` `ink-muted` sobre um fio `line`, como no Letterboxd. Não existe título de tela.

## Espaço, raio e layout

- Escala de 4px, `space-1` a `space-7`. Gutter lateral `space-4` no celular e `space-5` acima de 768px; conteúdo até `container-max`.
- `radius-sm` em tudo que se toca; `radius-md` só na capa em grade e na página do jogo. `radius-full` está reservado e não é usado.
- A coluna esquerda de toda linha tem `thumb-height`: capa de 33 por 44 ou bloco de data de 44 por 44. Assim todas as linhas de uma lista têm a mesma altura, com ou sem capa.
- A grade de capas usa `repeat(auto-fill, minmax(cover-min, 1fr))`, gap `space-4` por `space-3`. A capa é sempre `cover-ratio` com `poster-edge` interno; sem imagem, é `surface-sunken` com o título em `t-meta` no canto inferior. Nunca gradiente, nunca iniciais.
- Em Descobrir a capa leva o mesmo StatusMenu da Biblioteca, no canto superior esquerdo: `+ Adicionar` num jogo fora da biblioteca, o status num jogo dela. O título fica sempre embaixo da capa.
- Entrar e Criar conta são a única tela com capas de fundo: as do catálogo cobrem a tela sob `scrim`, sem etiqueta, e o formulário fica num painel `surface` com `radius-md`, o único cartão da tela, no centro acima de 768px e na base no celular. Maquete `maquetes/entrar-v2.html`, caminho C.

## Navegação

Acima de 768px: uma barra superior de `nav-height` com o wordmark, os destinos Início, Biblioteca, Comprar e Descobrir, e a busca à direita. Abaixo: a barra superior fica com wordmark e lupa, e os quatro destinos vão para uma barra inferior fixa de `nav-height`, só texto, com o mesmo indicador `red` do destino ativo. Não há barra lateral, menu hambúrguer nem ícone nos destinos.

Para a conta, Início é `/`: faixas pessoais de Jogando agora, Amigos jogando, Em promoção e Da sua lista. Biblioteca é `/biblioteca`, a grade com abas e filtros. Descobrir continua em `/descobrir`, para busca e listas do catálogo. A escolha A está em `maquetes/inicio-conta.html`.

### Busca única no topo

Existe um campo de busca, `Buscar no catálogo`, na barra superior de toda tela, e nenhum outro. Ele procura no catálogo inteiro do IGDB: em qualquer tela, enviar leva a Descobrir com o termo; em Descobrir, ele busca enquanto se digita. No celular, a lupa abre o mesmo campo por cima da barra, no lugar do wordmark, e ele fecha vazio. Nenhuma tela ganha um segundo campo de busca nem um filtro de título.

### Barra de filtros

Filtro de lista é uma linha logo abaixo das abas: rótulos em `t-label`, caixa alta, `ink-muted`, cada um com o chevron e um menu próprio em `surface-raised`, como o Letterboxd (Plataforma, Mídia, Ordem). Um filtro ativo mostra o valor escolhido em `ink`, e a opção atual do menu tem o marcador `red`. À direita, a contagem em `t-meta` (`21 jogos`). Não existe select nativo, chip solto nem segundo estilo de filtro; no celular a linha rola de lado. Ver `maquetes/biblioteca.html`.

### Área do visitante

Sem conta, o Dockd mostra só o catálogo (`maquetes/area-publica.html`). São públicos `/`, que vira a vitrine do catálogo em três faixas, Descobrir e a página do jogo, que mostra capa, ficha, plataformas e versões, sem status, preço, posse nem histórico. A barra do visitante tem Descobrir, a busca, Entrar e Criar conta; no celular, só Entrar, sem barra inferior. A etiqueta do visitante é `+ Adicionar`, que leva ao Entrar e volta à mesma capa com o menu aberto. Biblioteca, Comprar e tudo que grava exigem conta: abrir Comprar sem conta leva ao Entrar e volta para Comprar. Nenhum dado de uma conta aparece para o visitante, exceto o perfil público (`/u/:nome`) de quem o deixou Público.

## Perfil e amigos

Decidido em 28/09/2026 (`maquetes/perfil-social.html`: Estante, amigo B, privacidade A, entrada A). Cada conta tem um perfil em `/u/:nome`; o nome vem do e-mail na criação da conta, sem campo novo. O perfil é o primeiro item do menu da conta; não existe destino novo na barra.

- **Estante.** ProfileHead no topo: o nome em `t-display`, sem foto nem iniciais, `seguindo · seguidores` no metadado e FollowButton à direita. Embaixo, Jogando agora, Zerados e Quero em faixas de capas (sete, e `Ver todos` abre a grade), e Recente em linhas, uma por jogo, com o verbo do histórico (`Zerou`, `Começou a jogar`, `Quer`) e o tempo relativo. Backlog e Larguei ficam fora das faixas. As capas levam a etiqueta de quem olha, como em Descobrir.
- **Nunca no perfil:** preço visto ou pago, compra, Comprei, gasto, a fila de Comprar, versão vetada, mídia, loja, e-mail e token.
- **Seguir** é de um lado só. FollowButton diz `Seguir`, ou `Seguir de volta` quando a outra conta já segue; seguindo, diz `Seguindo`, e apontar mostra `Deixar de seguir` em `red-ink`. Clicar desfaz no lugar, sem confirmação; Seguir refaz. O visitante vai ao Entrar e volta ao perfil.
- **Amigo** é quem segue e é seguido. A marca é `Amigo` em `t-label` `ink-muted` ao lado do nome, no ProfileHead e nas listas; o botão continua `Seguindo`.
- **Listas.** `/u/:nome/seguidores` e `/u/:nome/seguindo`, em abas, uma PersonRow por conta: a capa do que ela joga agora na coluna da miniatura, o nome, `Jogando Título · N zerados` e FollowButton pequeno.
- **Privacidade.** O perfil é Público por padrão, aberto também ao visitante. No próprio perfil, uma Choice `Público · Só amigos` fica no lugar do botão Seguir. Com Só amigos, quem não é amigo vê o nome, as contagens e Seguir, e `Perfil só para amigos.`; não há pedido de aprovação, porque amigo já é quem a conta segue de volta.
- **Diário.** Decidido em 29/09/2026 (`maquetes/perfil-diario.html`, caminho A). `Ver diário`, no Recente, abre `/u/:nome/diario`: uma DiaryEntry por troca de status, da mais recente à mais antiga, com o DateBlock só na primeira linha do dia (nunca em `red`), a miniatura da capa, o título, a plataforma com o ExclusiveMark e o StatusChip do que a pessoa marcou. Entrar na biblioteca sem querer o jogo é Backlog. Compra, preço, posse com valor, veto e jogo que saiu da biblioteca ficam fora. Um dia com mais de dez linhas mostra dez e `Mais N neste dia` abre o resto no lugar. Só amigos fecha o Diário também.
- **Início.** A faixa Amigos jogando vem logo depois de Jogando agora e só aparece quando algum amigo joga algo: uma capa por jogo, com o nome do amigo no lugar da plataforma e a etiqueta de quem olha.

## Estados de um jogo

Um jogo tem um status visível, derivado do domínio (`ownerships` e `entries.play_state`), e é o único controle da página do jogo:

| Status | Quando | Chip |
| --- | --- | --- |
| Quero | sem posse e `purchase_intent` em want, planned ou preordered | preenchimento `gold`, texto `on-gold` |
| Backlog | com posse e `play_state` unplayed | preenchimento `ink` |
| Jogando | `play_state` playing ou paused | preenchimento `red` |
| Zerado | `play_state` finished | preenchimento `surface-sunken`, chip a 75%, capa a 55% |
| Larguei | `play_state` abandoned | preenchimento `line-strong`, texto `surface`, chip a 75%, capa a 55% |

A mídia é um segundo eixo, por versão: Físico, Digital ou Key card, sempre como MediaTag em `t-label`, nunca como cor nem como ícone.

O status só se troca pelo StatusMenu, o mesmo sobre a capa (Biblioteca, Descobrir) e na página do jogo: o chip atual é o controle, apontar para ele abre os outros estados embaixo, e clicar nele desmarca. No toque, o primeiro toque abre e o segundo desmarca. Desmarcar é a única forma de tirar um jogo da biblioteca: não há lixeira, link de remoção, confirmação nem aviso, e compra, preço visto e histórico ficam. Ver StatusMenu.

Na página do jogo, a plataforma não vai no texto do herói: fica na legenda da capa (`SWITCH · SWITCH 2`). A exclusividade é o ExclusiveMark sobre a capa, como na grade.

## Exclusivo

Decidido em 28/09/2026 (`maquetes/exclusivos.html`, desenho D, Silhueta). A exclusividade da obra nunca é texto: é o cartão de jogo do próprio console, a silhueta em retrato com o canto superior esquerdo chanfrado, em `gamecard` (preto) para exclusivo Nintendo e em `red` para exclusivo Switch 2. Multiplataforma não tem marca e não aparece escrito: a ausência já diz. Na linha, o cartão vem logo depois da plataforma, centrado nas letras do metadado; na capa da grade e da página do jogo, fica no canto inferior direito, longe do status. A miniatura da linha não recebe marca. Ver ExclusiveMark.

## Rodapé

Uma linha só no fim de toda tela, menos Entrar e Criar conta: wordmark pequeno, `Sobre` e `Dados de jogos por IGDB`, em `t-meta` `ink-muted` sobre um fio `line`, na largura do conteúdo. No celular termina acima da barra inferior. Sobre (`/sobre`) diz o que é o Dockd em no máximo três frases, sem título, slogan nem apresentação; o crédito do IGDB fica só no Footer. Termos e Privacidade entram na mesma linha só quando o Dockd abrir para outras pessoas. Ver Footer.

## Compra e preço

Decidido em 27/09/2026 (`maquetes/compra.html`, caminho A). O Dockd não guarda saldo de loja nem reserva: pediam que alguém atualizasse valores à mão.

- **Comprei** é um toque, com o mesmo componente em Comprar e na página do jogo. Com uma versão e uma mídia, grava a compra na hora pelo último preço visto daquela versão e mídia. Com mais de uma, as opções aparecem no lugar do botão, num Choice, e a escolha já é a compra. Depois, enquanto a tela está aberta, o controle mostra o que foi pago (ou `Sem valor`), que se clica para corrigir, e `Desfazer`. A linha de Comprar ganha a etiqueta Backlog e fica no lugar até a próxima visita.
- **O preço é o controle** do registro manual, como a etiqueta é o controle do status: clicar em `R$ 79,90` ou em `Sem preço` abre embaixo da linha Versão e Mídia (só quando há escolha), Preço visto e Onde, com os preços já vistos do jogo embaixo. Quem traz preço, em regra, é a sincronização; o registro manual é a exceção.
- **Promoção e menor preço já visto** entram só no preço da eShop, nunca no registro manual: preço riscado e `até dd/mm` em promoção vigente, `menor preço` somado quando esse preço também é o menor que o Dockd já viu, ou `menor preço desde dd/mm` sozinho fora de promoção. Ver Price.
- **Choice** substitui o select nativo: poucas opções reais, contorno `line-strong`, a escolhida em `ink`. Uma opção só não é escolha e aparece como texto. Erro aparece embaixo do campo em `red-ink`, nunca em aviso flutuante.
- **Totals** é a linha no topo de Comprar, no estilo do metadado: o total da fila por mídia, Digital e Físico separados pela mídia de cada jogo, cada um com a cobertura (`em 2 de 15`), `Agora` quando há jogo marcado e `Gasto em setembro` quando há compra no mês. A mídia que tem jogo e nenhum preço diz `Sem preço` e quantos jogos (`12 jogos`), para a separação ficar visível; mídia sem jogo não aparece.
- **Planejar a compra** (`maquetes/planejador.html`, caminho A, aprovado em 29/09/2026). Não há saldo de loja. Cada jogo em Quero tem uma mídia, Digital ou Físico, mostrada como MediaTag na meta da linha de Comprar logo depois da plataforma: a etiqueta é o controle e um toque troca, no lugar. O padrão é digital, porque a eShop vende quase tudo; físico só quando a conta escolheu. O preço da linha e o total seguem a mídia: um jogo físico mostra o preço físico registrado, ou `Sem preço`. **Promoções** abre Comprar com os digitais em promoção, pela data em que a oferta acaba; depois vêm Próximos lançamentos, Disponíveis e Sem data. **Agora** é um Button pequeno que fica marcado (preenchimento `ink`, como a opção escolhida do Choice), em qualquer jogo Quero com preço na mídia escolhida, físico ou digital: soma os marcados em dois subtotais que nunca se misturam, `Agora digital` e `Agora físico`, cada um só quando tem marcado (decidido em 29/09/2026, correção do mesmo dia: comparam com saldos diferentes, então nunca viram um total só). Marcar não muda o status nem entra no histórico, e trocar a mídia de um jogo marcado move o valor de um subtotal para o outro, sem desmarcar. Um jogo que troca de mídia fica na seção até a próxima visita.
- No histórico, `Comprou: R$ 79,90` marca o estado, e a posse que veio da compra não se repete como Registrou a posse.
- **Um jogo, várias edições.** Decidido em 28/09/2026: edição (Deluxe, pacote com conteúdo) e Nintendo Switch 2 Edition são versões do mesmo jogo, não outro jogo. O preço de um jogo em Comprar e no total estimado é o **menor preço vigente** entre as versões e edições que a conta não vetou; quando ele vem de uma edição que não é a padrão, a meta da linha ganha o nome curto dela (`Digital Deluxe`), e a plataforma já está na meta. Vetar a versão tira a edição da conta.
- **Comprei com edições** (`maquetes/edicoes.html`, caminho B, aprovado em 28/09/2026). Sem edição à venda, nada muda. Com edição, as opções abrem **embaixo da linha** (e embaixo do herói na página do jogo), porque o preço decide: a edição padrão de cada plataforma e mídia primeiro, depois as edições à venda da mais barata para a mais cara, cada uma com o Price e `Comprei esta`, que já é a compra e grava esse preço. Das edições, aparecem as duas mais baratas e `Mais N edições` mostra o resto no lugar; `Cancelar` fecha. Depois da compra a meta da linha diz a versão comprada (`Switch 2 · Digital Deluxe Edition`). A pergunta de posse ao marcar Backlog continua só com plataforma e mídia, e grava na edição padrão. Ver BuyOptions.

## Versões

Decidido em 28/09/2026 (`maquetes/edicoes.html`). A seção Versões da página do jogo não tem contagem: diria só 1 ou 2. É uma linha por plataforma, com a data, a edição padrão e o preço, como antes. As edições que a loja vende ficam embaixo da plataforma, recuadas, cada uma com o nome da loja, `Pacote · Digital` e o preço; a que a conta tem diz `Tem` e aparece sempre. Edição sem preço e que a conta não tem não aparece. Com mais de duas, aparecem as duas mais baratas e `Mais N edições` abre o resto no lugar (`Menos edições` fecha). A padrão que a loja deixou de vender diz `fora de venda`, e o preço do jogo vem da edição (Tony Hawk's 3 + 4 só se compra em pacote). O visitante vê só as plataformas.

## Conferir catálogo

Decidido em 27/09/2026 (`maquetes/casar-eshop.html`, caminho A) e ampliado em 28/09/2026 (`maquetes/edicoes.html`). O que o catálogo não resolve sozinho espera em `/conferir` (o endereço antigo, `/eshop`, continua abrindo), uma tela fora dos três destinos, aberta pelo item `Conferir catálogo` do menu da conta com a contagem das duas perguntas. O item some quando a fila esvazia. Qualquer conta decide, porque é dado do catálogo. Vazia, a tela diz `Nada para conferir.`

- **Mesmo jogo?** vem primeiro: o jogo que fica (a entrada principal no IGDB) e, embaixo, a entrada que pode ser ele e que está no catálogo como jogo à parte (remaster, Definitive, Anniversary, port). Edição e Nintendo Switch 2 Edition juntam sozinhas e nunca perguntam; remake nunca junta. `É o mesmo jogo` junta os dois: a outra entrada vira versão do jogo que fica, com posse, compras, preços, vetos e histórico. `É outro jogo` não pergunta de novo. As duas mudam a linha no lugar (`mesmo jogo`, `jogos diferentes`), com `Desfazer` enquanto a tela está aberta. Ver SameRow.
- **Na eShop**: a versão cujo produto a sincronização diária não achou com certeza. MatchRow é a versão (capa, título, plataforma e quantos candidatos) com até três produtos da loja embaixo, cada um com o preço no Brasil, `visto em` e `É este`. O título do produto abre a página dele no nintendo.com. `Não está na eShop` fecha a lista; é Button porque grava.
- Escolher e recusar mudam a linha no lugar: a versão passa a mostrar o produto e o preço, ou `fora da eShop`, com `Desfazer`, que traz os candidatos de volta. Sem diálogo nem aviso. A linha resolvida fica até a próxima visita.
- No celular o candidato ocupa duas linhas: o título inteiro, depois preço e botão.

## Histórico

O log de eventos vira um trilho vertical, do mais recente ao mais antigo, uma linha por ação: verbo em negrito, tempo relativo em `ink-muted` ao lado (`há 3 dias`), data exata e versão embaixo em `t-meta`. Dois marcadores e só: `red` na ação que definiu o estado atual, `ink` nas demais. Sem ícone por tipo de ação, sem agrupamento por mês. Ver History.

## Ícones

Heroicons outline em 24px, os mesmos que o projeto já carrega, em `currentColor`, inseridos inline pelo componente `<.icon>` do Phoenix. Um ícone entra só quando substitui a palavra que caberia ali, e são cinco casos: lupa na busca, seta para voltar, x para fechar, chevron nos menus da barra de filtros e da conta, mais para adicionar. Nenhum ícone em chip, tag, botão com rótulo ou destino de navegação. Sem emoji.

A única figura fora dos Heroicons é o cartão de jogo do ExclusiveMark, que substitui `Exclusivo Nintendo` e `Exclusivo Switch 2` e tem as cores do objeto, não `currentColor`.

## Movimento

Transição de 120ms em cor de fundo, borda e texto, em hover e pressionado. Nada mais se move. Respeita `prefers-reduced-motion`.

## Tema

O tema segue o sistema operacional. Não existe botão claro ou escuro na interface. `red` é o mesmo nos dois temas; tudo que é texto vermelho usa `red-ink`, que muda.

## Consumo no Phoenix

Os tokens entram em `assets/css/app.css` como `@theme` do Tailwind 4, com os mesmos nomes. Cada componente deste sistema vira uma função em `DockdWeb.Components` que emite exatamente as classes `dk-` de `components/bundle.css`; os testes de LiveView asseguram pelas classes e pelos textos definidos aqui. Nenhuma classe DaisyUI.
