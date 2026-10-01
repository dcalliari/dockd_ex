Favicon, ícone de app e thumbnail de link do Dockd: o "d." do wordmark, em branco sobre `red`, com o ponto em `ink` (direção B, Selo vermelho, decidida em 01/10/2026). Os glifos são os da Archivo 900 a 125% de largura, convertidos em caminhos, então os SVGs não dependem de fonte.

- `favicon.svg`: quadrado arredondado 64×64, a fonte do favicon e dos ícones do manifesto.
- `icone-app.svg`: o mesmo sem cantos transparentes, para o `apple-touch-icon` e o ícone maskable, que o sistema recorta.
- `thumbnail.svg`: 1200×630, a imagem de pré-visualização (`og:image`).

`gerar.sh` converte as fontes nos arquivos de `priv/static` (`favicon.svg`, `favicon.ico`, `apple-touch-icon.png`, `icon-*.png`, `images/og.png`); rode-o da raiz sempre que um SVG mudar e versione o resultado. O vermelho cheio como fundo vale só aqui, como ícone: na interface continua valendo a regra de cor de `design/README.md`.
