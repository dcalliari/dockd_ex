# NavBar
A navegação do Dockd em duas formas, com o mesmo vocabulário. Acima de 768px: barra superior de `nav-height` com o wordmark `dockd.`, os destinos Biblioteca, Comprar e Descobrir, e a busca à direita. Abaixo: a barra superior fica com wordmark e lupa, e os três destinos vão para uma barra inferior fixa de `nav-height`, só texto. O destino atual recebe `aria-current="page"` e 2px de `red`, embaixo no topo e em cima na barra inferior.

Sem barra lateral, sem menu hambúrguer, sem ícone nos destinos. O wordmark é texto em `t-wordmark`; só o ponto é `red`. O consumidor fornece `current` e o valor de busca. No celular o Footer, a última coisa da página, reserva `nav-height` mais `space-5` embaixo para não ficar sob a barra inferior.
