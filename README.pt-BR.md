# ImportMCP

[Read in English](README.md)

O ImportMCP é um plugin do Roblox Studio para trazer arquivos de fora para dentro de um place. Ele importa imagens PNG e JPEG, modelos 3D em GLB ou glTF e também áudio e vídeo. O plugin lê e decodifica os arquivos por conta própria e monta o resultado como instâncias de verdade, como ImageLabel, ImageButton, Decal ou Texture para imagens e Model ou MeshPart para modelos.

Existem dois modos de importação. No modo asset a importação vira um asset permanente. No modo sessão ela só existe em tempo de execução, enquanto a sessão estiver aberta. Tudo passa antes por uma área de staging, e os imports que você decide manter são restaurados automaticamente toda vez que o Studio abre. O painel permite importar arquivos e mostra o status, os imports persistidos e a fila do MCP.

A outra metade do projeto é a parte do MCP. O plugin roda um worker que pega pedidos de importação de uma fila, então um agente de IA conectado ao Studio consegue mandar um arquivo e ver ele aparecer no jogo sem ninguém clicar em nada. Ele foi feito para trabalhar junto com o meu Roblox Studio MCP, que tem ferramentas para enviar, importar e gerenciar esses assets, mas qualquer código pode usar o plugin direto fazendo require no módulo MCP.

## Como usar

Coloque a pasta ImportMCP dentro do ServerStorage mantendo a estrutura, usando o Rojo ou outra ferramenta de sincronização. Depois clique com o botão direito em ImportMCP.Main no Explorer e escolha Save as Local Plugin. Um botão ImportMCP aparece na aba Plugins e abre o painel, onde você escolhe os arquivos e alterna entre o modo asset e o modo sessão.

Para áudio e vídeo é preciso uma chave de API do Open Cloud do Roblox. Cole a chave no campo do painel e aperte Enter. Digitar limpar nesse campo remove a chave salva. Scripts e agentes usam o plugin fazendo require em game.ServerStorage.ImportMCP.MCP.

## Tempo de desenvolvimento

O ImportMCP levou uma semana para ser feito e está pronto para uso.

## Licença

GNU General Public License versão 3. O texto completo está no arquivo LICENSE.
