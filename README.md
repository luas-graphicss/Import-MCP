# ImportMCP

[Leia em português](README.pt-BR.md)

ImportMCP is a Roblox Studio plugin for bringing outside files into a place. It imports PNG and JPEG images, 3D models in GLB or glTF, and also audio and video. The plugin reads and decodes the files on its own and builds the result as real instances, like an ImageLabel, ImageButton, Decal or Texture for images and a Model or MeshPart for models.

There are two import modes. In asset mode the import becomes a permanent asset. In session mode it only exists at runtime, while the session is open. Everything goes through a staging area first, and the imports you decide to keep are restored automatically every time Studio opens. The panel lets you import files and shows the status, the persisted imports and the MCP queue.

The other half of the project is the MCP side. The plugin runs a worker that takes import requests from a queue, so an AI agent connected to Studio can send a file and see it show up in the game without anyone clicking anything. It was made to work together with my Roblox Studio MCP, which has tools to upload, import and manage these assets, but any code can use the plugin directly by requiring the MCP module.

## How to use

Put the ImportMCP folder inside ServerStorage keeping its structure, using Rojo or another sync tool. Then right click ImportMCP.Main in the Explorer and choose Save as Local Plugin. An ImportMCP button shows up in the Plugins tab and opens the panel, where you pick the files and switch between asset mode and session mode.

Audio and video need a Roblox Open Cloud API key. Paste it in the key field of the panel and press Enter. Typing limpar in that field removes the saved key. Scripts and agents use the plugin by requiring game.ServerStorage.ImportMCP.MCP.

## Development time

ImportMCP took one week to build and it is ready to use.

## License

GNU General Public License version 3. The full text is in the LICENSE file.
