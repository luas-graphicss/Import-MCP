local Modules=script.Parent.Parent
local Api=require(Modules.Api)
local Inbox=require(Modules.Transport.Inbox)
local Progress=require(Modules.Progress)
local Materialize=require(Modules.Runtime.Materialize)
local OpenCloud=require(Modules.Media.OpenCloud)
local StudioService=game:GetService("StudioService")

local MODE_LABELS={asset="Modo: asset permanente",session="Modo: sessao (runtime)"}

local EXTENSIONS={"png","jpg","jpeg","glb","gltf","bin","mp3","ogg","wav","flac","mp4","mov"}

return function(plugin,context)
	local Widget={}
	local COLORS={bg=Color3.fromRGB(37,37,40),panel=Color3.fromRGB(48,48,52),track=Color3.fromRGB(60,60,66),text=Color3.fromRGB(230,230,232),muted=Color3.fromRGB(160,160,168),accent=Color3.fromRGB(80,160,255),ok=Color3.fromRGB(96,200,120),bad=Color3.fromRGB(230,110,100)}

	local function padding(parent,all)
		local item=Instance.new("UIPadding")
		item.PaddingLeft=UDim.new(0,all)
		item.PaddingRight=UDim.new(0,all)
		item.PaddingTop=UDim.new(0,all)
		item.PaddingBottom=UDim.new(0,all)
		item.Parent=parent
		return item
	end

	local function textLabel(parent,text,order,color,size,height)
		local item=Instance.new("TextLabel")
		item.BackgroundTransparency=1
		item.Size=UDim2.new(1,0,0,height or 18)
		item.Font=Enum.Font.Gotham
		item.TextSize=size or 13
		item.TextColor3=color or COLORS.text
		item.TextXAlignment=Enum.TextXAlignment.Left
		item.TextWrapped=true
		item.TextTruncate=Enum.TextTruncate.AtEnd
		item.Text=text
		item.LayoutOrder=order
		item.Parent=parent
		return item
	end

	local info=DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right,false,false,320,460,260,240)
	local gui=plugin:CreateDockWidgetPluginGui("ImportMCP_Widget",info)
	gui.Title="ImportMCP"
	gui.Name="ImportMCP_Widget"
	gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

	local root=Instance.new("Frame")
	root.Size=UDim2.fromScale(1,1)
	root.BackgroundColor3=COLORS.bg
	root.BorderSizePixel=0
	root.Parent=gui
	padding(root,10)
	local layout=Instance.new("UIListLayout")
	layout.SortOrder=Enum.SortOrder.LayoutOrder
	layout.Padding=UDim.new(0,8)
	layout.Parent=root

	local title=textLabel(root,"ImportMCP  v"..Api.VERSION,1,COLORS.text,16,22)
	title.Font=Enum.Font.GothamBold
	local status=textLabel(root,"",2,COLORS.muted,12,52)
	local worker=textLabel(root,"",3,COLORS.muted,12,18)

	local importButton=Instance.new("TextButton")
	importButton.BackgroundColor3=COLORS.accent
	importButton.BorderSizePixel=0
	importButton.Size=UDim2.new(1,0,0,30)
	importButton.Font=Enum.Font.GothamBold
	importButton.TextSize=13
	importButton.TextColor3=COLORS.bg
	importButton.Text="Importar arquivos (imagem, GLB/glTF, audio, video)..."
	importButton.AutoButtonColor=true
	importButton.LayoutOrder=4
	importButton.Parent=root
	local importCorner=Instance.new("UICorner")
	importCorner.CornerRadius=UDim.new(0,4)
	importCorner.Parent=importButton

	 
	local keyBox=Instance.new("TextBox")
	keyBox.BackgroundColor3=COLORS.panel
	keyBox.BorderSizePixel=0
	keyBox.Size=UDim2.new(1,0,0,24)
	keyBox.Font=Enum.Font.Gotham
	keyBox.TextSize=12
	keyBox.TextColor3=COLORS.text
	keyBox.PlaceholderColor3=COLORS.muted
	keyBox.PlaceholderText="Chave Open Cloud para audio/video (cole aqui e pressione Enter)"
	keyBox.ClearTextOnFocus=false
	keyBox.TextXAlignment=Enum.TextXAlignment.Left
	keyBox.Text=""
	keyBox.LayoutOrder=5
	keyBox.Parent=root
	local keyCorner=Instance.new("UICorner")
	keyCorner.CornerRadius=UDim.new(0,4)
	keyCorner.Parent=keyBox
	local keyPadding=Instance.new("UIPadding")
	keyPadding.PaddingLeft=UDim.new(0,6)
	keyPadding.PaddingRight=UDim.new(0,6)
	keyPadding.Parent=keyBox

	local function refreshKeyPlaceholder()
		local state=OpenCloud.status()
		keyBox.PlaceholderText=state.configured and ("Chave Open Cloud configurada ("..tostring(state.keyPreview)..") - cole outra para trocar, ou 'limpar'") or "Chave Open Cloud para audio/video (cole aqui e pressione Enter)"
	end

	context.connect(keyBox.FocusLost,function(enterPressed)
		local text=keyBox.Text:gsub("^%s+",""):gsub("%s+$","")
		if text=="" then return end
		keyBox.Text=""
		if string.lower(text)=="limpar" or string.lower(text)=="clear" then
			OpenCloud.configure({apiKey=false})
			plugin:SetSetting("ImportMCP_OpenCloudKey",nil)
			context.log("Chave Open Cloud removida.")
		else
			local ok,err=pcall(OpenCloud.configure,{apiKey=text})
			if ok then
				plugin:SetSetting("ImportMCP_OpenCloudKey",text)
				context.log("Chave Open Cloud salva neste Studio; audios e videos importados passam a ser enviados pela Assets API.")
			else
				warn("ImportMCP: "..tostring(err))
			end
		end
		refreshKeyPlaceholder()
		Widget.refresh()
	end)
	refreshKeyPlaceholder()

	local buttons=Instance.new("Frame")
	buttons.BackgroundTransparency=1
	buttons.Size=UDim2.new(1,0,0,88)
	buttons.LayoutOrder=6
	buttons.Parent=root
	local modeButton
	local grid=Instance.new("UIGridLayout")
	grid.CellSize=UDim2.new(0.5,-4,0,24)
	grid.CellPadding=UDim2.new(0,8,0,8)
	grid.SortOrder=Enum.SortOrder.LayoutOrder
	grid.Parent=buttons

	local function button(text,order,callback)
		local item=Instance.new("TextButton")
		item.BackgroundColor3=COLORS.panel
		item.BorderSizePixel=0
		item.Font=Enum.Font.GothamMedium
		item.TextSize=12
		item.TextColor3=COLORS.text
		item.Text=text
		item.AutoButtonColor=true
		item.LayoutOrder=order
		item.Parent=buttons
		local corner=Instance.new("UICorner")
		corner.CornerRadius=UDim.new(0,4)
		corner.Parent=item
		context.connect(item.MouseButton1Click,function()
			local ok,err=pcall(callback)
			if not ok then warn("ImportMCP: "..tostring(err)) end
			Widget.refresh()
		end)
		return item
	end

	local list=Instance.new("ScrollingFrame")
	list.BackgroundColor3=COLORS.panel
	list.BorderSizePixel=0
	list.Size=UDim2.new(1,0,1,-290)
	list.CanvasSize=UDim2.new(0,0,0,0)
	list.AutomaticCanvasSize=Enum.AutomaticSize.Y
	list.ScrollBarThickness=6
	list.LayoutOrder=7
	list.Parent=root
	local listCorner=Instance.new("UICorner")
	listCorner.CornerRadius=UDim.new(0,4)
	listCorner.Parent=list
	local listLayout=Instance.new("UIListLayout")
	listLayout.SortOrder=Enum.SortOrder.LayoutOrder
	listLayout.Padding=UDim.new(0,2)
	listLayout.Parent=list
	local listPadding=padding(list,6)

	local progressInfo=DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,true,340,128,300,120)
	local progressGui=plugin:CreateDockWidgetPluginGui("ImportMCP_Progress",progressInfo)
	progressGui.Title="ImportMCP - Progresso"
	progressGui.Name="ImportMCP_Progress"
	progressGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	progressGui.Enabled=false

	local progressRoot=Instance.new("Frame")
	progressRoot.Size=UDim2.fromScale(1,1)
	progressRoot.BackgroundColor3=COLORS.bg
	progressRoot.BorderSizePixel=0
	progressRoot.Parent=progressGui
	padding(progressRoot,12)
	local progressLayout=Instance.new("UIListLayout")
	progressLayout.SortOrder=Enum.SortOrder.LayoutOrder
	progressLayout.Padding=UDim.new(0,6)
	progressLayout.Parent=progressRoot

	local progressName=textLabel(progressRoot,"",1,COLORS.text,14,20)
	progressName.Font=Enum.Font.GothamBold
	local progressStage=textLabel(progressRoot,"",2,COLORS.muted,12,18)
	local track=Instance.new("Frame")
	track.BackgroundColor3=COLORS.track
	track.BorderSizePixel=0
	track.Size=UDim2.new(1,0,0,10)
	track.LayoutOrder=3
	track.Parent=progressRoot
	local trackCorner=Instance.new("UICorner")
	trackCorner.CornerRadius=UDim.new(1,0)
	trackCorner.Parent=track
	local fill=Instance.new("Frame")
	fill.BackgroundColor3=COLORS.accent
	fill.BorderSizePixel=0
	fill.Size=UDim2.new(0,0,1,0)
	fill.Parent=track
	local fillCorner=Instance.new("UICorner")
	fillCorner.CornerRadius=UDim.new(1,0)
	fillCorner.Parent=fill
	local progressEta=textLabel(progressRoot,"",4,COLORS.muted,12,18)

	local function formatSeconds(seconds)
		if seconds<1 then return "menos de 1s" end
		if seconds<60 then return string.format("~%ds",math.ceil(seconds)) end
		return string.format("~%dmin %02ds",seconds//60,math.ceil(seconds%60))
	end

	local function formatBytes(bytes)
		bytes=bytes or 0
		if bytes>=1048576 then return string.format("%.1f MB",bytes/1048576) end
		if bytes>=1024 then return string.format("%.0f KB",bytes/1024) end
		return bytes.." B"
	end

	local autoOpened=false
	local hideAt=nil

	local function renderProgress(snapshot)
		local queued=#Inbox.list("queued")
		if snapshot.active then
			local batch=""
			if (snapshot.Total or 0)>1 then batch=string.format("  [%d de %d]",snapshot.Index or 1,snapshot.Total) end
			progressName.Text=string.format("%s (%s)%s",snapshot.Name or "Asset",formatBytes(snapshot.Bytes),batch)
			progressStage.Text=string.format("%s...   origem: %s",snapshot.label or "",snapshot.Source=="plugin" and "arquivos locais" or "agente MCP")
			progressStage.TextColor3=COLORS.muted
			fill.BackgroundColor3=COLORS.accent
			fill.Size=UDim2.new(snapshot.progress or 0,0,1,0)
			local eta=string.format("Restante: %s   Decorrido: %ds",formatSeconds(snapshot.remaining or 0),math.floor(snapshot.elapsed or 0))
			if queued>0 then eta=eta..string.format("   Fila: %d",queued) end
			progressEta.Text=eta
			if not progressGui.Enabled then
				progressGui.Enabled=true
				autoOpened=true
			end
			hideAt=nil
			return
		end
		if snapshot.Finished and snapshot.Finished>0 and snapshot.LastMessage then
			progressName.Text=snapshot.Name or "Asset"
			progressStage.Text=(snapshot.LastOk and "Concluido: " or "Falhou: ")..snapshot.LastMessage
			progressStage.TextColor3=snapshot.LastOk and COLORS.ok or COLORS.bad
			fill.BackgroundColor3=snapshot.LastOk and COLORS.ok or COLORS.bad
			fill.Size=UDim2.new(1,0,1,0)
			progressEta.Text=queued>0 and string.format("Proximo da fila em instantes (%d restantes)",queued) or "Nenhuma importacao em andamento."
		else
			progressName.Text="Nenhuma importacao em andamento."
			progressStage.Text=""
			fill.Size=UDim2.new(0,0,1,0)
			progressEta.Text=""
		end
		if autoOpened and progressGui.Enabled and queued==0 then
			hideAt=hideAt or os.clock()+4
			if os.clock()>=hideAt then
				progressGui.Enabled=false
				autoOpened=false
				hideAt=nil
			end
		end
	end

	function Widget.tickProgress()
		if not context.alive() then return end
		local ok,snapshot=pcall(Progress.snapshot)
		if ok then renderProgress(snapshot) end
	end

	function Widget.refresh()
		if not context.alive() then return end
		local state=Api.status()
		local runtime=state.runtime
		local createAsset=state.createAsset or {}
		local createAssetText=createAsset.state=="available" and "ok" or (createAsset.state=="unknown" and "nao testado" or "indisponivel")
		local cloud=state.openCloud or {}
		status.Text=string.format("Runtime: %s (v%s)   Permanentes: %d   Sessao: %d   Fila: %d\n%s   CreateAssetAsync: %s\nOpen Cloud (audio/video): %s   Midias pendentes: %d",runtime.installed and (runtime.upToDate and "instalado" or "desatualizado") or "ausente",tostring(runtime.version or "-"),state.permanent or 0,state.imports,state.queued,MODE_LABELS[state.mode] or state.mode,createAssetText,cloud.configured and "chave ok" or "sem chave",state.pendingMedia or 0)
		status.TextColor3=runtime.installed and runtime.upToDate and COLORS.ok or COLORS.bad
		if modeButton then modeButton.Text=MODE_LABELS[state.mode] or tostring(state.mode) end
		local work=context.worker
		worker.Text=work and (work.busy and "Worker: processando..." or string.format("Worker: ativo  ok=%d  falhas=%d  %s",work.processed,work.failed,work.lastMessage)) or "Worker: inativo"
		list:ClearAllChildren()
		listLayout.Parent=list
		listPadding.Parent=list
		for index,item in ipairs(Api.list()) do
			local color=COLORS.muted
			if item.status=="Ready" then color=COLORS.text elseif item.status=="Error" then color=COLORS.bad elseif item.status=="PendingUpload" then color=COLORS.accent end
			local row=textLabel(list,string.format("[%s] %s  (%s)%s",item.kind or "?",item.path,item.status or "-",item.error and ("\n"..item.error) or ""),index,color,11,30)
			row.TextYAlignment=Enum.TextYAlignment.Top
			row.TextTruncate=Enum.TextTruncate.None
		end
		for index,job in ipairs(Inbox.list()) do
			local row=textLabel(list,string.format("[fila] %s  %s  %s",job.FileName or job.id,job.State or "-",job.Local and formatBytes(job.Bytes) or ((job.Chunks or 0).." chunks")),1000+index,job.State=="failed" and COLORS.bad or COLORS.accent,11,18)
			row.TextTruncate=Enum.TextTruncate.AtEnd
		end
	end

	function Widget.importFiles()
		local ok,files=pcall(StudioService.PromptImportFiles,StudioService,EXTENSIONS)
		if not ok then
			warn("ImportMCP: "..tostring(files))
			return
		end
		if not files or #files==0 then return end
		local ids,count=context.worker.enqueueFiles(files,{})
		if count==0 then
			warn("ImportMCP: selecione ao menos um PNG, JPG, GLB, glTF, MP3, OGG, WAV, FLAC, MP4 ou MOV.")
			return
		end
		context.log(count.." arquivo(s) na fila; o worker importa um por vez.")
		progressGui.Enabled=true
		autoOpened=true
		Widget.refresh()
	end

	context.connect(importButton.MouseButton1Click,function()
		task.spawn(Widget.importFiles)
	end)

	modeButton=button(MODE_LABELS[Materialize.default()],1,function()
		local chosen=Materialize.default()=="asset" and "session" or "asset"
		Api.setMode(chosen)
		plugin:SetSetting("ImportMCP_Mode",chosen)
		context.log(chosen=="asset" and "Modo asset: cada import vira asset permanente da conta (requer o beta CreateAssetAsync Lua API)." or "Modo sessao: payload salvo no place e reconstruido a cada servidor/cliente.")
	end)
	button("Restaurar tudo",2,function() Api.restoreAll() end)
	button("Instalar runtime",3,function() Api.install(true) end)
	button("Limpar inbox",4,function() Api.upload.clear(false) end)
	button("Progresso",5,function() progressGui.Enabled=not progressGui.Enabled autoOpened=false end)
	button("Enviar midias pendentes",6,function()
		local items=Api.media.pending().items
		if #items==0 then
			context.log("Nenhum audio/video pendente.")
			return
		end
		if not OpenCloud.status().configured then
			warn("ImportMCP: cole a chave Open Cloud no campo acima antes de enviar audio/video.")
			return
		end
		task.spawn(function()
			local sent,failed=0,0
			for _,item in ipairs(items) do
				if not context.alive() then break end
				local result=Api.media.upload(item.path)
				if result.ok then sent+=1 else failed+=1 warn("ImportMCP: "..item.path.." -> "..tostring(result.error)) end
				if context.alive() then Widget.refresh() end
			end
			context.log(string.format("Midias enviadas: %d  falhas: %d",sent,failed))
		end)
	end)

	function Widget.toggle()
		gui.Enabled=not gui.Enabled
		if gui.Enabled then Widget.refresh() end
	end

	Widget.gui=gui
	Widget.progressGui=progressGui
	return Widget
end
