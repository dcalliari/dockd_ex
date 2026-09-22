# Auditoria visual inicial

Comparação feita entre a proposta persistida em `proposta.html` e a implementação da main `0ceb01e`, usando a aplicação local com o banco descartável. As diferenças abaixo foram registradas antes da rodada de ajuste. A implementação final fecha os itens com os tokens de `assets/css/app.css` e os componentes de `DockdWeb.DockdComponents`.

## Sistema comum

| Diferença visível | Status |
| --- | --- |
| A implementação usava lateral de 16rem, controles arredondados e espaçamentos maiores; a proposta usa lateral de 11rem, raio de 0,25rem e linhas finas. | Fechada |
| A implementação não tinha contexto no topo nem uma linguagem única para cabeçalho, título de seção, linha, capa, veredito e botão. | Fechada |
| O shell móvel usava cartões arredondados na navegação; a proposta usa barra inferior plana com quatro itens. | Fechada |
| A capa sem imagem usava tratamento diferente por tela; a proposta reserva a mesma proporção 3:4 e o mesmo fundo. | Fechada |
| A implementação usava caixas arredondadas e estados vazios tracejados; a proposta usa linhas e vazios sem caixa. | Fechada |

## Planejador

| Diferença visível | Status |
| --- | --- |
| A tela começava na conta da carteira, sem `Hoje`; a proposta começa com cabeçalho curto e contexto. | Fechada |
| A conta usava `Saldo`, `Reservado`, `Livre`; a proposta usa a conta em linha, com `Reservas`, livre destacado e ligação para Carteira. | Fechada |
| Lançamentos eram linhas sem bloco de data nem capa. | Fechada |
| O veredito aparecia como texto solto e era ocultado por seletor incorreto no celular. | Fechada |
| Compras eram exibidas em uma única lista e sem limite claro de itens. | Fechada |
| O agrupamento não mostrava a ação `Ver todos` como parte da seção. | Fechada |
| Jogar hoje tinha a hierarquia de recomendação, mas não compartilhava a linha de capa e botão. | Fechada |
| O backlog era um contador isolado com separação menos precisa. | Fechada |

## Biblioteca

| Diferença visível | Status |
| --- | --- |
| A grade iniciava em duas colunas e não reproduzia a grade de cinco colunas da proposta no desktop. | Fechada |
| A ação de estado vivia só no menu da capa; a proposta também mostra `Começar` ou `Alterar` no próprio item. | Fechada |
| O estado não tinha o mesmo chip sobre a capa, tipografia ou metadado de posse da proposta. | Fechada |
| Busca, abas e estado vazio usavam espaçamentos e bordas do DaisyUI, não os tokens da proposta. | Fechada |
| O editor continua disponível após a ação de editar para preservar o fluxo já coberto por testes; ele não aparece no estado inicial. | Justificada |

## Jogo

| Diferença visível | Status |
| --- | --- |
| A capa e o título usavam escala maior e cartões arredondados. | Fechada |
| A relação com o jogo, os dados e as versões não compartilhavam a hierarquia proposta. | Fechada |
| Cada versão era um cartão separado; a proposta usa tabela de linhas com data, disponibilidade, preço e veredito. | Fechada |
| As ações estavam espalhadas entre cartões; agora ficam na linha da versão e usam os botões comuns. | Fechada |
| Formulários de observação, compra e veto continuam em `details` para preservar o comportamento existente, mas abrem dentro da linha. | Justificada |
| A volta preserva `Planejador`, `Biblioteca` ou `Descobrir` por `from`, como aprovado na proposta. | Fechada |

## Descobrir

| Diferença visível | Status |
| --- | --- |
| A tela tinha nome e ação de página, mas não possuía filtro visual de plataforma. | Fechada |
| A grade não usava a escala e a proporção únicas de capa. | Fechada |
| O estado de relação e `Adicionar à lista` não usavam a mesma linguagem de ação. | Fechada |
| O estado vazio era apenas texto central, sem a mesma linha de estado da Biblioteca. | Fechada |

## Carteira

| Diferença visível | Status |
| --- | --- |
| A tela repetia a equação como cartão; a proposta usa resumo de saldo e uma lista de reservas. | Fechada |
| Saldo vazio mostrava formulário como ação principal sem hierarquia compartilhada. | Fechada |
| Reservas usavam superfície arredondada e título pesado; agora são linhas com capa ausente, jogo, valor e editar. | Fechada |
| Faltava ligação explícita do efeito da carteira no planejador. | Fechada |

## Responsividade e tema

| Diferença visível | Status |
| --- | --- |
| No celular a conta quebrava com o livre sem hierarquia suficiente. | Fechada com a quebra em duas faixas do token `wallet-line` |
| A barra inferior, grades e linhas não tinham o mesmo comportamento em 375 px. | Fechada |
| Claro e escuro herdavam componentes DaisyUI diferentes entre telas. | Fechada com tokens `dockd-line`, `dockd-muted`, `dockd-faint` |
| Formulários e o editor permanecem funcionais em claro e escuro. | Fechada |

## Strings longas mantidas

As únicas strings com mais de seis palavras mantidas são mensagens de estado e confirmação que explicam um dado ausente ou uma ação irreversível: `Não informado`, `Explore o catálogo para acompanhar datas.`, `Reserve um lançamento para vê-lo no planejador.`, `Excluir esta reserva?` e os textos de confirmação de remoção já cobertos pelos fluxos existentes. Títulos, rótulos e motivos de decisão foram reduzidos a dados curtos.
