local Config = {
    Players = {
        Killer   = {Color = Color3.fromRGB(255, 93, 108)},
        Survivor = {Color = Color3.fromRGB(64, 224, 255)}
    },
    Objects = {
        Generator = {Color = Color3.fromRGB(150, 0, 200)},
        Gate      = {Color = Color3.fromRGB(255, 255, 255)},
        Pallet    = {Color = Color3.fromRGB(74, 255, 181)},
        Window    = {Color = Color3.fromRGB(74, 255, 181)},
        Hook      = {Color = Color3.fromRGB(132, 255, 169)}
    },
    HITBOX_Enabled      = false,
    HITBOX_Size         = 10,
    HITBOX_Transparency = 1,
    HITBOX_ESP          = false,
    HITBOX_ESP_Color    = Color3.fromRGB(255, 50, 50)
}

local MaskNames = {
    ["Richard"] = "Rooster", ["Tony"]   = "Tiger",
    ["Brandon"] = "Panther", ["Cobra"]  = "Cobra",
    ["Richter"] = "Rat",     ["Rabbit"] = "Rabbit",
    ["Alex"]    = "Chainsaw"
}
local MaskColors = {
    ["Richard"] = Color3.fromRGB(255, 0, 0),
    ["Tony"]    = Color3.fromRGB(255, 255, 0),
    ["Brandon"] = Color3.fromRGB(160, 32, 240),
    ["Cobra"]   = Color3.fromRGB(0, 255, 0),
    ["Richter"] = Color3.fromRGB(0, 0, 0),
    ["Rabbit"]  = Color3.fromRGB(255, 105, 180),
    ["Alex"]    = Color3.fromRGB(255, 255, 255)
}

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService          = game:GetService("GuiService")
local Lighting            = game:GetService("Lighting")
local TweenService        = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local ActiveGenerators    = {}
local LastUpdateTick      = 0
local LastFullESPRefresh  = 0
local OriginalHitboxSizes = {}
local HitboxESPBoxes      = {}
local ESPDrawingEnabled   = false

local TouchID    = 8822
local ActionPath = "Survivor-mob.Controls.action.check"
local HeartbeatConnection  = nil
local VisibilityConnection = nil
local IndicatorGui         = nil

local speedHackEnabled      = false
local desiredSpeed          = 16
local speedConnections      = {}
local autoSkillcheckEnabled = true
local fullbrightEnabled     = true
local isMinimized           = false
local noclipEnabled         = false
local noclipConn            = nil

-- =============================================
-- HELPERS
-- =============================================

local function GetRole()
    local team = LocalPlayer.Team
    if not team then return "None" end
    local n = team.Name:lower()
    if n:find("killer")   then return "Killer"   end
    if n:find("survivor") then return "Survivor" end
    return "None"
end

local function IsSurvivor(player)
    if not player.Team then return false end
    return player.Team.Name:lower():find("survivor") ~= nil
end

local function GetGameValue(obj, name)
    if not obj then return nil end
    local attr = obj:GetAttribute(name)
    if attr ~= nil then return attr end
    local child = obj:FindFirstChild(name)
    if child then
        local ok, val = pcall(function() return child.Value end)
        if ok then return val end
    end
    return nil
end

local function Notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = title,
            Text     = text,
            Icon     = "rbxassetid://4483345998",
            Duration = duration or 3,
        })
    end)
end

-- =============================================
-- SPEED HACK
-- =============================================

local function applySpeed(humanoid)
    if humanoid and speedHackEnabled then
        humanoid.WalkSpeed = desiredSpeed
    end
end

local function setupSpeedEnforcement(humanoid)
    for _, c in ipairs(speedConnections) do c:Disconnect() end
    speedConnections = {}
    if not humanoid then return end
    applySpeed(humanoid)
    table.insert(speedConnections, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedHackEnabled and humanoid.WalkSpeed ~= desiredSpeed then
            humanoid.WalkSpeed = desiredSpeed
        end
    end))
end

local function onCharacterAddedSpeed(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if humanoid then setupSpeedEnforcement(humanoid) end
end

-- =============================================
-- NOCLIP
-- =============================================

local function StartNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not noclipEnabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end

local function StopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    local char = LocalPlayer.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = true end
    end
end

-- =============================================
-- GATE TELEPORT
-- =============================================

local function TeleportToNearestGate()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local Map = workspace:FindFirstChild("Map") or workspace
    local nearest, nearestDist = nil, math.huge
    for _, obj in ipairs(Map:GetDescendants()) do
        if obj.Name == "Gate" then
            local part = obj:IsA("BasePart") and obj
                or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")))
            if part then
                local dist = (myRoot.Position - part.Position).Magnitude
                if dist < nearestDist then nearest = part; nearestDist = dist end
            end
        end
    end
    if nearest then
        myRoot.CFrame = CFrame.new(nearest.Position + Vector3.new(0, 4, 0))
        Notify("Gate TP", "Teleported to nearest gate!")
    else
        Notify("Gate TP", "No gate found!")
    end
end

-- =============================================
-- TELEPORT TO PLAYER
-- =============================================

local function TeleportToPlayer(targetName)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local target = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Name:lower():find(targetName:lower()) then
            target = p; break
        end
    end
    if not target or not target.Character then
        Notify("Teleport", "Player not found!"); return
    end
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if targetRoot then
        myRoot.CFrame = CFrame.new(targetRoot.Position + Vector3.new(2, 0, 2))
        Notify("Teleport", "Teleported to " .. target.Name .. "!")
    end
end

-- =============================================
-- ESP DRAWING
-- =============================================

local function CheckDrawingSupport()
    local ok = pcall(function() local t = Drawing.new("Line"); t:Remove() end)
    ESPDrawingEnabled = ok
end
CheckDrawingSupport()

local function CreateHitboxESPBox(player)
    if not ESPDrawingEnabled or HitboxESPBoxes[player] then return end
    local drawings = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Thickness = 2; line.Color = Color3.fromRGB(255,255,255)
        line.Transparency = 1; line.Visible = false
        table.insert(drawings, line)
    end
    local nl = Drawing.new("Text")
    nl.Size = 13; nl.Center = true; nl.Outline = true
    nl.Color = Config.HITBOX_ESP_Color; nl.Visible = false
    table.insert(drawings, nl)
    local dl = Drawing.new("Text")
    dl.Size = 11; dl.Center = true; dl.Outline = true
    dl.Color = Color3.fromRGB(255,255,255); dl.Visible = false
    table.insert(drawings, dl)
    HitboxESPBoxes[player] = {
        drawings  = drawings,
        cornerTL1 = drawings[1], cornerTL2 = drawings[2],
        cornerTR1 = drawings[3], cornerTR2 = drawings[4],
        cornerBL1 = drawings[5], cornerBL2 = drawings[6],
        cornerBR1 = drawings[7], cornerBR2 = drawings[8],
        nameLabel = drawings[9], distLabel = drawings[10],
    }
end

local function RemoveHitboxESPBox(player)
    if not HitboxESPBoxes[player] then return end
    for _, d in ipairs(HitboxESPBoxes[player].drawings) do
        pcall(function() d:Remove() end)
    end
    HitboxESPBoxes[player] = nil
end

local function RemoveAllHitboxESPBoxes()
    for p in pairs(HitboxESPBoxes) do RemoveHitboxESPBox(p) end
    HitboxESPBoxes = {}
end

local function UpdateHitboxESPBox(player)
    if not ESPDrawingEnabled then return end
    if not Config.HITBOX_ESP then RemoveHitboxESPBox(player); return end
    if not player.Character then RemoveHitboxESPBox(player); return end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    local hum  = player.Character:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then RemoveHitboxESPBox(player); return end
    if not HitboxESPBoxes[player] then CreateHitboxESPBox(player) end
    local esp = HitboxESPBoxes[player]
    if not esp then return end
    local cam = workspace.CurrentCamera
    local hs  = Config.HITBOX_Size / 2
    local pos = root.Position
    local c3d = {
        pos+Vector3.new(-hs, hs,-hs), pos+Vector3.new( hs, hs,-hs),
        pos+Vector3.new( hs,-hs,-hs), pos+Vector3.new(-hs,-hs,-hs),
        pos+Vector3.new(-hs, hs, hs), pos+Vector3.new( hs, hs, hs),
        pos+Vector3.new( hs,-hs, hs), pos+Vector3.new(-hs,-hs, hs),
    }
    local anyOn = false
    local mnX,mnY,mxX,mxY = math.huge,math.huge,-math.huge,-math.huge
    for _, c in ipairs(c3d) do
        local sp, on = cam:WorldToViewportPoint(c)
        if on then anyOn = true end
        if sp.Z > 0 then
            mnX=math.min(mnX,sp.X); mnY=math.min(mnY,sp.Y)
            mxX=math.max(mxX,sp.X); mxY=math.max(mxY,sp.Y)
        end
    end
    if not anyOn or mnX == math.huge then
        for _, d in ipairs(esp.drawings) do d.Visible = false end; return
    end
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local dist   = myRoot and math.floor((root.Position-myRoot.Position).Magnitude) or 0
    local cl     = math.clamp(math.min((mxX-mnX)*0.25,(mxY-mnY)*0.25),4,20)
    local w      = Color3.fromRGB(255,255,255)
    esp.cornerTL1.From=Vector2.new(mnX,mnY); esp.cornerTL1.To=Vector2.new(mnX+cl,mnY); esp.cornerTL1.Color=w; esp.cornerTL1.Visible=true
    esp.cornerTL2.From=Vector2.new(mnX,mnY); esp.cornerTL2.To=Vector2.new(mnX,mnY+cl); esp.cornerTL2.Color=w; esp.cornerTL2.Visible=true
    esp.cornerTR1.From=Vector2.new(mxX,mnY); esp.cornerTR1.To=Vector2.new(mxX-cl,mnY); esp.cornerTR1.Color=w; esp.cornerTR1.Visible=true
    esp.cornerTR2.From=Vector2.new(mxX,mnY); esp.cornerTR2.To=Vector2.new(mxX,mnY+cl); esp.cornerTR2.Color=w; esp.cornerTR2.Visible=true
    esp.cornerBL1.From=Vector2.new(mnX,mxY); esp.cornerBL1.To=Vector2.new(mnX+cl,mxY); esp.cornerBL1.Color=w; esp.cornerBL1.Visible=true
    esp.cornerBL2.From=Vector2.new(mnX,mxY); esp.cornerBL2.To=Vector2.new(mnX,mxY-cl); esp.cornerBL2.Color=w; esp.cornerBL2.Visible=true
    esp.cornerBR1.From=Vector2.new(mxX,mxY); esp.cornerBR1.To=Vector2.new(mxX-cl,mxY); esp.cornerBR1.Color=w; esp.cornerBR1.Visible=true
    esp.cornerBR2.From=Vector2.new(mxX,mxY); esp.cornerBR2.To=Vector2.new(mxX,mxY-cl); esp.cornerBR2.Color=w; esp.cornerBR2.Visible=true
    local tn = (player.Team and player.Team.Name:lower()) or ""
    local bc = Config.HITBOX_ESP_Color
    if tn:find("killer") then bc = Config.Players.Killer.Color
    elseif tn:find("survivor") then bc = Config.Players.Survivor.Color end
    local bn = player.Name
    local ska = player:GetAttribute("SelectedKiller")
    if tn:find("killer") and ska and tostring(ska) ~= "" then bn = tostring(ska) end
    esp.nameLabel.Text = bn
    esp.nameLabel.Position = Vector2.new((mnX+mxX)/2, mnY-16)
    esp.nameLabel.Color = bc; esp.nameLabel.Visible = true
    esp.distLabel.Text = "["..dist.." studs]"
    esp.distLabel.Position = Vector2.new((mnX+mxX)/2, mxY+2)
    esp.distLabel.Visible = true
end

-- =============================================
-- CORE ESP
-- =============================================

local function SetupGui()
    if PlayerGui:FindFirstChild("ChasedInds") then
        PlayerGui:FindFirstChild("ChasedInds"):Destroy()
    end
    IndicatorGui = Instance.new("ScreenGui")
    IndicatorGui.Name           = "ChasedInds"
    IndicatorGui.IgnoreGuiInset = true
    IndicatorGui.DisplayOrder   = 999
    IndicatorGui.ResetOnSpawn   = false
    IndicatorGui.Parent         = PlayerGui
end

local function ApplyHighlight(object, color)
    local h = object:FindFirstChild("H") or Instance.new("Highlight")
    h.Name="H"; h.Adornee=object; h.FillColor=color; h.OutlineColor=color
    h.FillTransparency=0.8; h.OutlineTransparency=0.3
    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=object
end

local function CreateBillboardTag(text, color, size, textSize)
    local bb = Instance.new("BillboardGui")
    bb.Name="BitchHook"; bb.AlwaysOnTop=true
    bb.Size=size or UDim2.new(0,120,0,30)
    local lbl = Instance.new("TextLabel")
    lbl.Name="BitchHook"; lbl.Size=UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency=1; lbl.Text=text; lbl.TextColor3=color
    lbl.TextStrokeTransparency=0; lbl.TextStrokeColor3=Color3.new(0,0,0)
    lbl.Font=Enum.Font.GothamBold; lbl.TextSize=textSize or 10
    lbl.TextWrapped=true; lbl.RichText=true; lbl.Parent=bb
    return bb
end

local function updatePlayerNametag(player)
    if not IndicatorGui or not IndicatorGui.Parent then return end
    if not player.Character then
        for _, n in ipairs({player.Name, player.Name.."_Chased", player.Name.."_Killer"}) do
            local m = IndicatorGui:FindFirstChild(n) if m then m:Destroy() end
        end
        return
    end
    local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not rootPart then return end
    local tn  = (player.Team and player.Team.Name:lower()) or ""
    local ska = GetGameValue(player, "SelectedKiller")
    local isKnocked = GetGameValue(player.Character, "Knocked")
    local isHooked  = GetGameValue(player.Character, "IsHooked")
    local isChased  = GetGameValue(player.Character, "IsChased")
    local isKiller  = tn:find("killer") ~= nil
    local color = isKiller and Config.Players.Killer.Color or Config.Players.Survivor.Color
    if isHooked then color = Color3.fromRGB(255,182,193)
    elseif humanoid and humanoid.Health < humanoid.MaxHealth then
        color = isKnocked and Color3.fromRGB(200,100,0) or Color3.fromRGB(200,200,0)
    end
    local dist = 0
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        dist = math.floor((rootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude)
    end
    local baseName = (isKiller and ska and tostring(ska)~="") and tostring(ska) or player.Name
    local nameText = baseName.."\n["..dist.." studs]"
    local billboard = rootPart:FindFirstChild("BitchHook")
    if not billboard then
        billboard = CreateBillboardTag(nameText, color)
        billboard.Adornee=rootPart; billboard.Parent=rootPart
    else
        local lbl = billboard:FindFirstChild("BitchHook") or billboard:FindFirstChildOfClass("TextLabel")
        if lbl then lbl.Text=nameText; lbl.TextColor3=color end
    end
    ApplyHighlight(player.Character, color)
    local rawMask = GetGameValue(player,"Mask") or GetGameValue(player.Character,"Mask")
    local hasMask = false
    if isKiller and string.match(tostring(ska):lower(),"masked") and rawMask then
        for key, name in pairs(MaskNames) do
            if key:lower()==tostring(rawMask):lower() then
                hasMask = true
                local mb = rootPart:FindFirstChild("MaskHook")
                if not mb then
                    mb = CreateBillboardTag(name, MaskColors[key] or Color3.new(1,1,1), UDim2.new(0,100,0,20), 12)
                    mb.Name="MaskHook"; mb.StudsOffset=Vector3.new(0,3,0)
                    mb.Adornee=rootPart; mb.Parent=rootPart
                else
                    local lbl = mb:FindFirstChild("BitchHook") or mb:FindFirstChildOfClass("TextLabel")
                    if lbl then lbl.Text=name; lbl.TextColor3=MaskColors[key] or Color3.new(1,1,1) end
                end
                break
            end
        end
    end
    if not hasMask then
        local mb = rootPart:FindFirstChild("MaskHook") if mb then mb:Destroy() end
    end
    local cl2d = IndicatorGui:FindFirstChild(player.Name.."_Chased")
    if isChased then
        local ct3 = billboard:FindFirstChild("ChasedLabel")
        if not ct3 then
            ct3=Instance.new("TextLabel",billboard); ct3.Name="ChasedLabel"
            ct3.Size=UDim2.new(1,0,1,0); ct3.Position=UDim2.new(0,0,-1.2,0)
            ct3.BackgroundTransparency=1; ct3.Font=Enum.Font.GothamBold; ct3.TextSize=24
        end
        ct3.Text="!!"; ct3.TextColor3=color; ct3.TextStrokeTransparency=0
        if not cl2d then
            cl2d=Instance.new("TextLabel",IndicatorGui); cl2d.Name=player.Name.."_Chased"
            cl2d.BackgroundTransparency=1; cl2d.Font=Enum.Font.GothamBold; cl2d.TextSize=24
            cl2d.TextStrokeTransparency=0; cl2d.AnchorPoint=Vector2.new(0.5,0.5)
            cl2d.Size=UDim2.new(0,40,0,40)
        end
        cl2d.Text="!!"; cl2d.TextColor3=color
        local sp, on = workspace.CurrentCamera:WorldToScreenPoint(rootPart.Position)
        if on then cl2d.Visible=false
        else
            cl2d.Visible=true
            local vc=workspace.CurrentCamera.ViewportSize/2
            local dir=Vector2.new(sp.X,sp.Y)-vc
            if sp.Z<0 then dir=-dir end
            local ms=math.max(math.abs(dir.X)/(vc.X-30),math.abs(dir.Y)/(vc.Y-30))
            cl2d.Position=UDim2.new(0,vc.X+dir.X/(ms==0 and 1 or ms),0,vc.Y+dir.Y/(ms==0 and 1 or ms))
        end
    else
        if cl2d then cl2d:Destroy() end
        local ct3 = billboard and billboard:FindFirstChild("ChasedLabel")
        if ct3 then ct3:Destroy() end
    end
    local kl2d = IndicatorGui:FindFirstChild(player.Name.."_Killer")
    if isKiller then
        if not kl2d then
            kl2d=Instance.new("TextLabel",IndicatorGui); kl2d.Name=player.Name.."_Killer"
            kl2d.BackgroundTransparency=1; kl2d.Font=Enum.Font.GothamBold; kl2d.TextSize=10
            kl2d.TextStrokeTransparency=0; kl2d.Size=UDim2.new(0,120,0,30)
            kl2d.RichText=true; kl2d.AnchorPoint=Vector2.new(0.5,0.5)
        end
        kl2d.Text=baseName.."\n["..dist.." studs]"; kl2d.TextColor3=color
        local sp, on = workspace.CurrentCamera:WorldToScreenPoint(rootPart.Position)
        if not on then
            kl2d.Visible=true
            local vc=workspace.CurrentCamera.ViewportSize/2
            local dir=Vector2.new(sp.X,sp.Y)-vc
            if sp.Z<0 then dir=-dir end
            local ms=math.max(math.abs(dir.X)/(vc.X-30),math.abs(dir.Y)/(vc.Y-30))
            kl2d.Position=UDim2.new(0,vc.X+dir.X/(ms==0 and 1 or ms),0,vc.Y+dir.Y/(ms==0 and 1 or ms))
        else kl2d.Visible=false end
    elseif kl2d then kl2d:Destroy() end
    if Config.HITBOX_ESP and ESPDrawingEnabled then UpdateHitboxESPBox(player)
    elseif HitboxESPBoxes[player] then RemoveHitboxESPBox(player) end
end

local function updateGeneratorProgress(generator)
    if not generator or not generator.Parent then return true end
    local percent = GetGameValue(generator,"RepairProgress") or GetGameValue(generator,"Progress") or 0
    local billboard = generator:FindFirstChild("GenBitchHook")
    if percent >= 100 then
        if billboard then billboard:Destroy() end
        local h = generator:FindFirstChild("H") if h then h:Destroy() end
        return true
    end
    local cp = math.clamp(percent,0,100)
    local finalColor = cp < 50
        and Config.Objects.Generator.Color:Lerp(Color3.fromRGB(180,180,0), cp/50)
        or  Color3.fromRGB(180,180,0):Lerp(Color3.fromRGB(0,150,0), (cp-50)/50)
    local percentStr = string.format("[%.1f%%]", percent)
    if not billboard then
        billboard = CreateBillboardTag(percentStr, finalColor)
        billboard.Name="GenBitchHook"; billboard.StudsOffset=Vector3.new(0,2,0)
        billboard.Adornee=generator:FindFirstChild("defaultMaterial",true) or generator
        billboard.Parent=generator
    else
        local lbl = billboard:FindFirstChild("BitchHook") or billboard:FindFirstChildOfClass("TextLabel")
        if lbl then lbl.Text=percentStr; lbl.TextColor3=finalColor end
    end
    return false
end

local function updateNextKillerDisplay()
    if not IndicatorGui or not IndicatorGui.Parent then return end
    local label = IndicatorGui:FindFirstChild("NextKillerDisplay")
    local tn    = (LocalPlayer.Team and LocalPlayer.Team.Name:lower()) or ""
    if tn:find("spectator") or tn:find("lobby") then
        if not label then
            label=Instance.new("TextLabel",IndicatorGui); label.Name="NextKillerDisplay"
            label.Size=UDim2.new(0,220,0,30); label.Position=UDim2.new(0.5,0,0,45)
            label.AnchorPoint=Vector2.new(0.5,0); label.BackgroundTransparency=0.5
            label.BackgroundColor3=Color3.new(0,0,0); label.TextColor3=Color3.new(1,1,1)
            label.Font=Enum.Font.GothamBold; label.TextSize=14; label.RichText=true
            label.Text="Next Killer: Calculating..."
        end
        local plrs = Players:GetPlayers()
        table.sort(plrs, function(a,b)
            local aA=GetGameValue(a,"AllowKiller") or false
            local bA=GetGameValue(b,"AllowKiller") or false
            if aA~=bA then return aA==true end
            return (GetGameValue(a,"KillerChance") or 0)>(GetGameValue(b,"KillerChance") or 0)
        end)
        local nk=plrs[1]
        if nk then
            label.Text="Next Killer: <font color=\"rgb(255,0,0)\">"
                ..(nk==LocalPlayer and "YOU" or tostring(GetGameValue(nk,"SelectedKiller") or nk.Name))
                .."</font>"
        end
    elseif label then label:Destroy() end
end

-- FIX: Pallet freeze — use task.spawn so highlight never blocks main thread
local function RefreshESP()
    task.spawn(function()
        ActiveGenerators = {}
        local Map = workspace:FindFirstChild("Map")
        if not Map then return end
        for _, obj in ipairs(Map:GetDescendants()) do
            task.wait() -- yield each iteration to prevent freeze
            if obj.Name == "Generator" and obj:IsA("Model") then
                ApplyHighlight(obj, Config.Objects.Generator.Color)
                table.insert(ActiveGenerators, obj)
            elseif obj.Name == "Window" then
                ApplyHighlight(obj, Config.Objects.Window.Color)
            elseif obj.Name == "Hook" then
                local m = obj:FindFirstChild("Model")
                if m then
                    for _, p in ipairs(m:GetDescendants()) do
                        if p:IsA("MeshPart") then ApplyHighlight(p, Config.Objects.Hook.Color) end
                    end
                end
            elseif obj.Name=="Palletwrong" or obj.Name=="Pallet" then
                -- FIX: wrap in pcall, don't yield on pallet highlight
                pcall(function() ApplyHighlight(obj, Config.Objects.Pallet.Color) end)
            elseif obj.Name == "Gate" then
                ApplyHighlight(obj, Config.Objects.Gate.Color)
            end
        end
    end)
end

-- FIX: Listen for new pallets dropped and highlight without freezing
local function WatchForPallets()
    local Map = workspace:FindFirstChild("Map")
    if not Map then return end
    Map.DescendantAdded:Connect(function(obj)
        if obj.Name == "Palletwrong" or obj.Name == "Pallet" then
            task.spawn(function()
                task.wait(0.1)
                pcall(function() ApplyHighlight(obj, Config.Objects.Pallet.Color) end)
            end)
        end
    end)
end

local function GetActionTarget()
    local current = PlayerGui
    for seg in string.gmatch(ActionPath,"[^%.]+") do
        current = current and current:FindFirstChild(seg)
    end
    return current
end

local function TriggerMobileButton()
    local b = GetActionTarget()
    if b and b:IsA("GuiObject") then
        local p,s,i = b.AbsolutePosition, b.AbsoluteSize, GuiService:GetGuiInset()
        local cx,cy = p.X+(s.X/2)+i.X, p.Y+(s.Y/2)+i.Y
        pcall(function()
            VirtualInputManager:SendTouchEvent(TouchID,0,cx,cy)
            task.wait(0.01)
            VirtualInputManager:SendTouchEvent(TouchID,2,cx,cy)
        end)
    end
end

local function InitializeAutobuy()
    if not autoSkillcheckEnabled then return end
    task.spawn(function()
        local prompt = PlayerGui:WaitForChild("SkillCheckPromptGui",10)
        local check  = prompt and prompt:WaitForChild("Check",10)
        if not check then return end
        local line,goal = check:WaitForChild("Line"), check:WaitForChild("Goal")
        if VisibilityConnection then VisibilityConnection:Disconnect() end
        VisibilityConnection = check:GetPropertyChangedSignal("Visible"):Connect(function()
            if LocalPlayer.Team and LocalPlayer.Team.Name=="Survivors" and check.Visible and autoSkillcheckEnabled then
                if HeartbeatConnection then HeartbeatConnection:Disconnect() end
                HeartbeatConnection = RunService.Heartbeat:Connect(function()
                    local lr=line.Rotation%360; local gr=goal.Rotation%360
                    local ss,se=(gr+101)%360,(gr+115)%360
                    if (ss>se and (lr>=ss or lr<=se)) or (lr>=ss and lr<=se) then
                        TriggerMobileButton()
                        if HeartbeatConnection then HeartbeatConnection:Disconnect(); HeartbeatConnection=nil end
                    end
                end)
            elseif HeartbeatConnection then
                HeartbeatConnection:Disconnect(); HeartbeatConnection=nil
            end
        end)
    end)
end

local function UpdateHitboxes()
    local function restoreAll()
        for player,origSize in pairs(OriginalHitboxSizes) do
            if player and player.Character then
                local root=player.Character:FindFirstChild("HumanoidRootPart")
                if root then root.Size=origSize; root.Transparency=1; root.CanCollide=true end
            end
        end
        OriginalHitboxSizes={}
    end
    if GetRole()~="Killer" or not Config.HITBOX_Enabled then restoreAll(); return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer and IsSurvivor(player) then
            local char=player.Character
            if char then
                local root=char:FindFirstChild("HumanoidRootPart")
                local hum=char:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health>0 then
                    if not OriginalHitboxSizes[player] then OriginalHitboxSizes[player]=root.Size end
                    root.Size=Vector3.new(Config.HITBOX_Size,Config.HITBOX_Size,Config.HITBOX_Size)
                    root.CanCollide=false; root.Transparency=Config.HITBOX_Transparency
                elseif root and OriginalHitboxSizes[player] then
                    root.Size=OriginalHitboxSizes[player]; root.Transparency=1
                    root.CanCollide=true; OriginalHitboxSizes[player]=nil
                end
            end
        end
    end
end

-- =============================================
-- UI — 300px wide, shorter height
-- =============================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name="YutzzHUB"; ScreenGui.IgnoreGuiInset=true
ScreenGui.DisplayOrder=9999; ScreenGui.ResetOnSpawn=false
ScreenGui.Enabled=true; ScreenGui.Parent=PlayerGui

local UI_WIDTH     = 300
local UI_HEIGHT    = 340  -- shorter
local TITLE_HEIGHT = 32

local MainFrame = Instance.new("Frame")
MainFrame.Name="MainFrame"
MainFrame.Size=UDim2.new(0,UI_WIDTH,0,UI_HEIGHT)
MainFrame.Position=UDim2.new(0,8,0.5,-UI_HEIGHT/2)
MainFrame.BackgroundColor3=Color3.fromRGB(20,20,30)
MainFrame.BorderSizePixel=0; MainFrame.Active=true
MainFrame.Draggable=true; MainFrame.Parent=ScreenGui

local originalSize = MainFrame.Size

Instance.new("UICorner",MainFrame).CornerRadius=UDim.new(0,8)
local mstroke=Instance.new("UIStroke",MainFrame)
mstroke.Color=Color3.fromRGB(100,100,255); mstroke.Thickness=1.2

local TitleBar=Instance.new("Frame",MainFrame)
TitleBar.Name="TitleBar"; TitleBar.Size=UDim2.new(1,0,0,TITLE_HEIGHT)
TitleBar.BackgroundColor3=Color3.fromRGB(30,30,50); TitleBar.BorderSizePixel=0
Instance.new("UICorner",TitleBar).CornerRadius=UDim.new(0,8)
local tf=Instance.new("Frame",TitleBar)
tf.Size=UDim2.new(1,0,0.5,0); tf.Position=UDim2.new(0,0,0.5,0)
tf.BackgroundColor3=Color3.fromRGB(30,30,50); tf.BorderSizePixel=0

local TitleLabel=Instance.new("TextLabel",TitleBar)
TitleLabel.Size=UDim2.new(1,-45,1,0); TitleLabel.Position=UDim2.new(0,8,0,0)
TitleLabel.BackgroundTransparency=1; TitleLabel.Text="YutzzHUB"
TitleLabel.TextColor3=Color3.fromRGB(255,255,255); TitleLabel.Font=Enum.Font.GothamBold
TitleLabel.TextSize=12; TitleLabel.TextXAlignment=Enum.TextXAlignment.Left

local SubLabel=Instance.new("TextLabel",TitleBar)
SubLabel.Size=UDim2.new(1,-45,1,0); SubLabel.Position=UDim2.new(0,8,0,0)
SubLabel.BackgroundTransparency=1; SubLabel.Text="Violence District"
SubLabel.TextColor3=Color3.fromRGB(130,130,255); SubLabel.Font=Enum.Font.Gotham
SubLabel.TextSize=9; SubLabel.TextXAlignment=Enum.TextXAlignment.Right

local MinimizeBtn=Instance.new("TextButton",TitleBar)
MinimizeBtn.Size=UDim2.new(0,24,0,16); MinimizeBtn.Position=UDim2.new(1,-30,0.5,-8)
MinimizeBtn.BackgroundColor3=Color3.fromRGB(60,60,90); MinimizeBtn.Text="-"
MinimizeBtn.TextColor3=Color3.fromRGB(255,255,255); MinimizeBtn.Font=Enum.Font.GothamBold
MinimizeBtn.TextSize=13; MinimizeBtn.BorderSizePixel=0
Instance.new("UICorner",MinimizeBtn).CornerRadius=UDim.new(0,4)

local ContentFrame=Instance.new("ScrollingFrame",MainFrame)
ContentFrame.Name="ContentFrame"
ContentFrame.Size=UDim2.new(1,-8,1,-(TITLE_HEIGHT+6))
ContentFrame.Position=UDim2.new(0,4,0,TITLE_HEIGHT+2)
ContentFrame.BackgroundTransparency=1; ContentFrame.BorderSizePixel=0
ContentFrame.ScrollBarThickness=3
ContentFrame.ScrollBarImageColor3=Color3.fromRGB(100,100,255)
ContentFrame.CanvasSize=UDim2.new(0,0,0,0)
ContentFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y
ContentFrame.ScrollingDirection=Enum.ScrollingDirection.Y
ContentFrame.ElasticBehavior=Enum.ElasticBehavior.Never

local ContentLayout=Instance.new("UIListLayout",ContentFrame)
ContentLayout.Padding=UDim.new(0,3); ContentLayout.SortOrder=Enum.SortOrder.LayoutOrder

local ContentPadding=Instance.new("UIPadding",ContentFrame)
ContentPadding.PaddingTop=UDim.new(0,3); ContentPadding.PaddingLeft=UDim.new(0,3)
ContentPadding.PaddingRight=UDim.new(0,3); ContentPadding.PaddingBottom=UDim.new(0,6)

ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ContentFrame.CanvasSize=UDim2.new(0,0,0,ContentLayout.AbsoluteContentSize.Y+12)
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(MainFrame,TweenInfo.new(0.3),{Size=UDim2.new(0,UI_WIDTH,0,TITLE_HEIGHT)}):Play()
        ContentFrame.Visible=false; MinimizeBtn.Text="+"
    else
        TweenService:Create(MainFrame,TweenInfo.new(0.3),{Size=originalSize}):Play()
        ContentFrame.Visible=true; MinimizeBtn.Text="-"
    end
end)

-- =============================================
-- UI PROTECTION
-- =============================================

local function ProtectUI()
    task.spawn(function()
        while true do
            task.wait(0.5)
            if not ScreenGui or not ScreenGui.Parent then
                pcall(function() ScreenGui.Parent=PlayerGui end)
            end
            if ScreenGui then
                if not ScreenGui.Enabled then ScreenGui.Enabled=true end
                if ScreenGui.DisplayOrder~=9999 then ScreenGui.DisplayOrder=9999 end
            end
            if MainFrame and not MainFrame.Visible then MainFrame.Visible=true end
        end
    end)
end

PlayerGui.ChildAdded:Connect(function()
    task.wait(0.2)
    pcall(function()
        if not ScreenGui.Parent then ScreenGui.Parent=PlayerGui end
        ScreenGui.Enabled=true; ScreenGui.DisplayOrder=9999
        if MainFrame then MainFrame.Visible=true end
    end)
end)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
    task.wait(0.3)
    pcall(function()
        if not ScreenGui.Parent then ScreenGui.Parent=PlayerGui end
        ScreenGui.Enabled=true; ScreenGui.DisplayOrder=9999
        if MainFrame then MainFrame.Visible=true end
    end)
end)

-- =============================================
-- UI BUILDERS
-- =============================================

local function CreateSectionLabel(text)
    local f=Instance.new("Frame",ContentFrame)
    f.Size=UDim2.new(1,0,0,20); f.BackgroundColor3=Color3.fromRGB(35,35,60); f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,5)
    local l=Instance.new("TextLabel",f)
    l.Size=UDim2.new(1,-8,1,0); l.Position=UDim2.new(0,8,0,0)
    l.BackgroundTransparency=1; l.Text=text
    l.TextColor3=Color3.fromRGB(130,130,255); l.Font=Enum.Font.GothamBold
    l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left
    return f
end

local function CreateToggle(labelText, default, callback)
    local f=Instance.new("Frame",ContentFrame)
    f.Size=UDim2.new(1,0,0,26); f.BackgroundColor3=Color3.fromRGB(28,28,45); f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,5)
    local l=Instance.new("TextLabel",f)
    l.Size=UDim2.new(1,-50,1,0); l.Position=UDim2.new(0,8,0,0)
    l.BackgroundTransparency=1; l.Text=labelText
    l.TextColor3=Color3.fromRGB(220,220,220); l.Font=Enum.Font.Gotham
    l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left
    local bg=Instance.new("Frame",f)
    bg.Size=UDim2.new(0,36,0,18); bg.Position=UDim2.new(1,-42,0.5,-9)
    bg.BackgroundColor3=default and Color3.fromRGB(100,100,255) or Color3.fromRGB(60,60,80)
    bg.BorderSizePixel=0
    Instance.new("UICorner",bg).CornerRadius=UDim.new(1,0)
    local knob=Instance.new("Frame",bg)
    knob.Size=UDim2.new(0,12,0,12)
    knob.Position=default and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
    knob.BackgroundColor3=Color3.fromRGB(255,255,255); knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)
    local state=default or false
    local btn=Instance.new("TextButton",f)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    btn.MouseButton1Click:Connect(function()
        state=not state
        TweenService:Create(bg,TweenInfo.new(0.2),{BackgroundColor3=state and Color3.fromRGB(100,100,255) or Color3.fromRGB(60,60,80)}):Play()
        TweenService:Create(knob,TweenInfo.new(0.2),{Position=state and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
        callback(state)
    end)
    return f
end

local function CreateTextbox(labelText, placeholder, callback)
    local f=Instance.new("Frame",ContentFrame)
    f.Size=UDim2.new(1,0,0,46); f.BackgroundColor3=Color3.fromRGB(28,28,45); f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,5)
    local l=Instance.new("TextLabel",f)
    l.Size=UDim2.new(1,-8,0,16); l.Position=UDim2.new(0,8,0,3)
    l.BackgroundTransparency=1; l.Text=labelText
    l.TextColor3=Color3.fromRGB(220,220,220); l.Font=Enum.Font.Gotham
    l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left
    local ib=Instance.new("TextBox",f)
    ib.Size=UDim2.new(1,-16,0,20); ib.Position=UDim2.new(0,8,0,22)
    ib.BackgroundColor3=Color3.fromRGB(40,40,65); ib.Text=""
    ib.TextColor3=Color3.fromRGB(255,255,255); ib.PlaceholderText=placeholder or "Enter value..."
    ib.PlaceholderColor3=Color3.fromRGB(120,120,150); ib.Font=Enum.Font.Gotham
    ib.TextSize=11; ib.BorderSizePixel=0; ib.ClearTextOnFocus=false
    Instance.new("UICorner",ib).CornerRadius=UDim.new(0,4)
    ib.FocusLost:Connect(function(enter) if enter then callback(ib.Text) end end)
    return f
end

local function CreateButton(labelText, callback)
    local f=Instance.new("Frame",ContentFrame)
    f.Size=UDim2.new(1,0,0,26); f.BackgroundColor3=Color3.fromRGB(28,28,45); f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,5)
    local btn=Instance.new("TextButton",f)
    btn.Size=UDim2.new(1,-16,1,-6); btn.Position=UDim2.new(0,8,0,3)
    btn.BackgroundColor3=Color3.fromRGB(60,60,100); btn.Text=labelText
    btn.TextColor3=Color3.fromRGB(255,255,255); btn.Font=Enum.Font.GothamBold
    btn.TextSize=11; btn.BorderSizePixel=0
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,5)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(100,100,200)}):Play()
        task.wait(0.1)
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(60,60,100)}):Play()
        callback()
    end)
    return f
end

-- =============================================
-- BUILD UI
-- =============================================

CreateSectionLabel("⚡ Player Settings")

CreateToggle("Speed Hack", false, function(state)
    speedHackEnabled=state
    local hum=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not state and hum then
        hum.WalkSpeed=16
        for _,c in ipairs(speedConnections) do c:Disconnect() end
        speedConnections={}
    elseif state and hum then setupSpeedEnforcement(hum) end
end)

CreateTextbox("WalkSpeed", "Default: 16", function(input)
    local s=tonumber(input)
    if s then
        desiredSpeed=s; speedHackEnabled=true
        local hum=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        applySpeed(hum)
    end
end)

CreateToggle("Noclip", false, function(state)
    noclipEnabled=state
    if state then StartNoclip() else StopNoclip() end
end)

CreateSectionLabel("🎯 Hitbox Settings")

CreateToggle("Enable Hitbox", false, function(state)
    Config.HITBOX_Enabled=state
    if not state then
        for player,origSize in pairs(OriginalHitboxSizes) do
            if player and player.Character then
                local root=player.Character:FindFirstChild("HumanoidRootPart")
                if root then root.Size=origSize; root.Transparency=1; root.CanCollide=true end
            end
        end
        OriginalHitboxSizes={}
    end
end)

CreateTextbox("Hitbox Size", "Default: 10", function(input)
    local s=tonumber(input) if s and s>0 then Config.HITBOX_Size=s end
end)

CreateTextbox("Hitbox Transparency", "0-1 (1=invisible)", function(input)
    local t=tonumber(input) if t and t>=0 and t<=1 then Config.HITBOX_Transparency=t end
end)

CreateToggle("Hitbox ESP", false, function(state)
    Config.HITBOX_ESP=state
    if not state then RemoveAllHitboxESPBoxes() end
end)

CreateSectionLabel("🔧 Game Settings")

CreateToggle("Auto Skillcheck", true, function(state)
    autoSkillcheckEnabled=state
    if state then InitializeAutobuy()
    else
        if HeartbeatConnection then HeartbeatConnection:Disconnect(); HeartbeatConnection=nil end
        if VisibilityConnection then VisibilityConnection:Disconnect(); VisibilityConnection=nil end
    end
end)

CreateToggle("Fullbright", true, function(state)
    fullbrightEnabled=state
    if not state then
        Lighting.Ambient=Color3.fromRGB(127,127,127)
        Lighting.OutdoorAmbient=Color3.fromRGB(127,127,127)
        Lighting.Brightness=1; Lighting.ClockTime=14
        Lighting.GlobalShadows=true; Lighting.FogEnd=100000
    end
end)

CreateSectionLabel("🚪 Teleport")

CreateButton("Teleport to Nearest Gate", function()
    TeleportToNearestGate()
end)

CreateTextbox("Teleport to Player", "Enter player name...", function(input)
    if input and input~="" then TeleportToPlayer(input) end
end)

-- =============================================
-- CONNECTIONS
-- =============================================

workspace.ChildAdded:Connect(function(c)
    if c.Name=="Map" then
        task.wait(1)
        LastFullESPRefresh=0
        RefreshESP()
        WatchForPallets()
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    if HeartbeatConnection then HeartbeatConnection:Disconnect() end
    if VisibilityConnection then VisibilityConnection:Disconnect() end
    SetupGui(); RemoveAllHitboxESPBoxes()
    task.wait(1); InitializeAutobuy()
    onCharacterAddedSpeed(char); OriginalHitboxSizes={}
    if noclipEnabled then StartNoclip() end
end)

Players.PlayerRemoving:Connect(function(player)
    OriginalHitboxSizes[player]=nil; RemoveHitboxESPBox(player)
    if not IndicatorGui then return end
    for _,n in ipairs({player.Name.."_Chased",player.Name.."_Killer",player.Name}) do
        local obj=IndicatorGui:FindFirstChild(n) if obj then obj:Destroy() end
    end
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if Config.HITBOX_ESP and ESPDrawingEnabled then CreateHitboxESPBox(player) end
    end)
    player.CharacterRemoving:Connect(function() RemoveHitboxESPBox(player) end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player~=LocalPlayer then
        player.CharacterAdded:Connect(function()
            task.wait(0.5)
            if Config.HITBOX_ESP and ESPDrawingEnabled then CreateHitboxESPBox(player) end
        end)
        player.CharacterRemoving:Connect(function() RemoveHitboxESPBox(player) end)
    end
end

-- =============================================
-- MAIN LOOP
-- =============================================

local espUpdateIndex = 1
local allPlayers     = {}

RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - LastUpdateTick < 0.05 then return end
    LastUpdateTick = now

    if fullbrightEnabled then
        Lighting.Ambient=Color3.fromRGB(255,255,255)
        Lighting.OutdoorAmbient=Color3.fromRGB(255,255,255)
        Lighting.Brightness=2; Lighting.ClockTime=14
        Lighting.GlobalShadows=false; Lighting.FogEnd=9e9
    end

    if now - LastFullESPRefresh > 8 then
        LastFullESPRefresh=now; RefreshESP()
    end

    updateNextKillerDisplay()
    UpdateHitboxes()

    local myChar       = LocalPlayer.Character
    local myRoot       = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local killerNearby = false

    allPlayers = Players:GetPlayers()

    -- One player nametag update per frame
    if #allPlayers > 0 then
        espUpdateIndex = (espUpdateIndex % #allPlayers) + 1
        local p = allPlayers[espUpdateIndex]
        if p and p~=LocalPlayer then
            updatePlayerNametag(p)
        end
    end

    -- Killer nearby check (all players, lightweight)
    for _, p in ipairs(allPlayers) do
        if p~=LocalPlayer then
            local pTeam = p.Team and p.Team.Name:lower() or ""
            if pTeam:find("killer") and myRoot and p.Character
                and p.Character:FindFirstChild("HumanoidRootPart") then
                if (p.Character.HumanoidRootPart.Position-myRoot.Position).Magnitude < 99 then
                    killerNearby=true
                end
            end
        end
    end

    if Config.HITBOX_ESP and ESPDrawingEnabled then
        for _, p in ipairs(allPlayers) do
            if p~=LocalPlayer then UpdateHitboxESPBox(p) end
        end
    end

    if myRoot then
        local warn = myRoot:FindFirstChild("KillerWarn")
        if killerNearby then
            if not warn then
                warn=CreateBillboardTag("!",Color3.fromRGB(255,0,0),UDim2.new(0,50,0,50),40)
                warn.Name="KillerWarn"; warn.StudsOffset=Vector3.new(0,4,0)
                warn.Adornee=myRoot; warn.Parent=myRoot
            end
        elseif warn then warn:Destroy() end
    end

    -- Generator progress — one per frame
    if #ActiveGenerators > 0 then
        local idx = (math.floor(now*10) % #ActiveGenerators)+1
        local g = ActiveGenerators[idx]
        if g then
            if updateGeneratorProgress(g) then table.remove(ActiveGenerators,idx) end
        end
    end
end)

-- =============================================
-- INIT
-- =============================================

SetupGui()
RefreshESP()
WatchForPallets()
InitializeAutobuy()
ProtectUI()

if LocalPlayer.Character then onCharacterAddedSpeed(LocalPlayer.Character) end