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

- Escreva em pt-BR, na voz de quem usa: **+ Adicionar**, **Comprei**, **Reservar**, **Registrar preço**. O botão diz o que acontece; nunca "Salvar" ou "Confirmar".
- Nenhuma string de interface passa de seis palavras. Exceções: estado vazio, confirmação de ação irreversível e as três frases de Sobre.
- Sem slogan, subtítulo, eyebrow ou sermão. A navegação já diz onde a pessoa está; a tela não repete o nome em um título grande.
- Cada informação aparece uma vez por tela. Um valor padrão não é informação: um jogo sem preço observado não mostra "R$ 0,00" nem "Sem alvo", mostra `Sem preço` uma vez, em `ink-muted`.
- Preço nunca é "preço atual". É `t-num` com `visto em dd/mm/aaaa` em `t-meta`. Passados 30 dias, a data fica em `warn` com a palavra desatualizado.
- Datas em `dd/mm/aaaa`; mês abreviado em caixa alta sem ponto no bloco de data (`SET`, `OUT`). Dinheiro em `R$ 1.249,90`.
- Metadado separado por ponto mediano: `Switch 2 · 2026 · Team Cherry`. Nunca vírgula, nunca barra, nunca espaço duplo.
- Sem emoji, sem ponto de exclamação.
- O crédito do IGDB (`Dados de jogos por IGDB`) fica em `t-meta`, `ink-muted`, no fim de onde os dados do IGDB aparecem: na página do jogo, na mesma linha do link `Mais informações no IGDB`, e no fim dos resultados de uma busca em Descobrir. Fora disso, só na linha do Footer e em Sobre.

## Cor

- A página é `surface`; o texto é `ink`; o metadado é `ink-muted`. Não existe um terceiro nível de cinza: se algo não merece `ink-muted`, não merece estar na tela.
- `red` é preenchimento em quatro lugares e só neles: o botão primário da tela, o chip Jogando, o indicador da aba e do destino ativos, o ponto do wordmark. Como texto e contorno, use `red-ink`, que escurece no claro e clareia no escuro para manter contraste.
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

Acima de 768px: uma barra superior de `nav-height` com o wordmark, os destinos Biblioteca, Comprar e Descobrir, e a busca à direita. Abaixo: a barra superior fica com wordmark e lupa, e os três destinos vão para uma barra inferior fixa de `nav-height`, só texto, com o mesmo indicador `red` do destino ativo. Não há barra lateral, menu hambúrguer nem ícone nos destinos.

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

O status só se troca pelo StatusMenu, o mesmo sobre a capa (Biblioteca, Descobrir) e na página do jogo: o chip atual é o controle, apontar para ele abre os outros estados embaixo, e clicar nele desmarca. No toque, o primeiro toque abre e o segundo desmarca. Desmarcar é a única forma de tirar um jogo da biblioteca: não há lixeira, link de remoção, confirmação nem aviso, e compra, preço visto, saldo e histórico ficam. Ver StatusMenu.

Na página do jogo, plataforma e exclusividade da obra não vão no texto do herói: ficam na legenda da capa, `SWITCH 2` à esquerda e `EXCLUSIVO` em `red-ink` à direita, e só quando a obra é exclusiva.

## Rodapé

Uma linha só no fim de toda tela, menos Entrar e Criar conta: wordmark pequeno, `Sobre` e `Dados de jogos por IGDB`, em `t-meta` `ink-muted` sobre um fio `line`, na largura do conteúdo. No celular termina acima da barra inferior. Sobre (`/sobre`) diz o que é o Dockd em no máximo três frases, sem título, slogan nem apresentação, e leva o crédito do IGDB. Termos e Privacidade entram na mesma linha só quando o Dockd abrir para outras pessoas. Ver Footer.

## Histórico

O log de eventos vira um trilho vertical, do mais recente ao mais antigo, uma linha por ação: verbo em negrito, tempo relativo em `ink-muted` ao lado (`há 3 dias`), data exata e versão embaixo em `t-meta`. Dois marcadores e só: `red` na ação que definiu o estado atual, `ink` nas demais. Sem ícone por tipo de ação, sem agrupamento por mês. Ver History.

## Ícones

Heroicons outline em 24px, os mesmos que o projeto já carrega, em `currentColor`, inseridos inline pelo componente `<.icon>` do Phoenix. Um ícone entra só quando substitui a palavra que caberia ali, e são cinco casos: lupa na busca, seta para voltar, x para fechar, chevron nos menus da barra de filtros e da conta, mais para adicionar. Nenhum ícone em chip, tag, botão com rótulo ou destino de navegação. Sem emoji.

## Movimento

Transição de 120ms em cor de fundo, borda e texto, em hover e pressionado. Nada mais se move. Respeita `prefers-reduced-motion`.

## Tema

O tema segue o sistema operacional. Não existe botão claro ou escuro na interface. `red` é o mesmo nos dois temas; tudo que é texto vermelho usa `red-ink`, que muda.

## Consumo no Phoenix

Os tokens entram em `assets/css/app.css` como `@theme` do Tailwind 4, com os mesmos nomes. Cada componente deste sistema vira uma função em `DockdWeb.Components` que emite exatamente as classes `dk-` de `components/bundle.css`; os testes de LiveView asseguram pelas classes e pelos textos definidos aqui. Nenhuma classe DaisyUI.
