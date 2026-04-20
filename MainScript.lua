    -- MainScript.lua
    -- Box ESP (Drawing lib) + Velocity Speed (JopLib UI) + Overwatch Bypass

    -- ============================================================
    -- JOPLIB SETUP
    -- ============================================================

    local repo = "https://raw.githubusercontent.com/Tzvyy/JopLib/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local Elements = loadstring(game:HttpGet(repo .. "Elements.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "SaveManager.lua"))()

    Elements:Setup(Library)
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)

    -- Instance-scoped proxy tables (safe with multiple scripts)
    local Toggles = Library.Toggles
    local Options = Library.Options

    local Window = Library:CreateWindow({
        Title = "Game Utility",
        Center = true,
        AutoShow = true,
        TabPadding = 8,
    })

    local Tabs = {
        Combat = Window:AddTab("Combat"),
        Visuals = Window:AddTab("Visuals"),
        Movement = Window:AddTab("Movement"),
        ["UI Settings"] = Window:AddTab("UI Settings"),
    }

    -- ============================================================
    -- SERVICES
    -- ============================================================

    local players = game:GetService("Players")
    local runService = game:GetService("RunService")
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local userInputService = game:GetService("UserInputService")
    local camera = workspace.CurrentCamera
    local localPlayer = players.LocalPlayer

    local debugLog = false
    local scriptUnloaded = false
    local function dlog(msg)
        if debugLog then print("[Debug] " .. msg) end
    end

    local function hideESPDrawings(esp)
        for key, drawing in pairs(esp) do
            if key == "bones" then
                for _, bone in ipairs(drawing) do bone.Visible = false end
            else
                drawing.Visible = false
            end
        end
    end

    -- ============================================================
    -- BYPASS (runs immediately, UI added later in UI Settings tab)
    -- ============================================================

    local bypassStatus = "Inactive"

    local overwatch = replicatedStorage:FindFirstChild("Remotes")
        and replicatedStorage.Remotes:FindFirstChild("Overwatch")

    if overwatch then
        if typeof(getconnections) == "function" then
            for _, conn in ipairs(getconnections(overwatch.OnClientEvent)) do
                conn:Disable()
            end
        end

        pcall(function()
            game:GetService("ContextActionService"):UnbindAction("freezePlayer")
        end)

        if typeof(getconnections) == "function" then
            task.spawn(function()
                while task.wait(5) do
                    if scriptUnloaded then break end
                    for _, conn in ipairs(getconnections(overwatch.OnClientEvent)) do
                        if conn.Enabled then conn:Disable() end
                    end
                end
            end)
        end

        bypassStatus = "Active"
    end

    local honeypotNames = { "GodMode", "Test", "Trap" }
    local remotesFolder = replicatedStorage:FindFirstChild("Remotes")

    if remotesFolder and typeof(hookfunction) == "function" then
        local oldFire = Instance.new("RemoteEvent").FireServer
        hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            if self and self.Parent == remotesFolder then
                for _, name in ipairs(honeypotNames) do
                    if self.Name == name then return end
                end
            end
            return oldFire(self, ...)
        end)
    end

    -- ============================================================
    -- BOX ESP (Drawing Library)
    -- ============================================================

    local espObjects = {} -- [player] = { box, name, healthBar, healthOutline }

    local espSettings = {
        Enabled = false,
        ShowBox = true,
        ShowNames = true,
        ShowHealth = true,
        ShowDistance = true,
        ShowSkeleton = false,
        NameType = "Display Name",
        BoxColor = Color3.fromRGB(255, 50, 50),
        NameColor = Color3.fromRGB(255, 255, 255),
        HealthColor = Color3.fromRGB(0, 255, 0),
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        MaxDistance = 1000,
        BoxThickness = 1.5,
        FontSize = 14,
    }

    -- Skeleton joint connections for R15 characters.
    local skeletonJoints = {
        {"Head", "UpperTorso"},
        {"UpperTorso", "LowerTorso"},
        {"UpperTorso", "LeftUpperArm"},
        {"LeftUpperArm", "LeftLowerArm"},
        {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"},
        {"RightUpperArm", "RightLowerArm"},
        {"RightLowerArm", "RightHand"},
        {"LowerTorso", "LeftUpperLeg"},
        {"LeftUpperLeg", "LeftLowerLeg"},
        {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"},
        {"RightUpperLeg", "RightLowerLeg"},
        {"RightLowerLeg", "RightFoot"},
    }

    local function createESP(player)
        if espObjects[player] then return end

        local box = Drawing.new("Square")
        box.Visible = false
        box.Color = espSettings.BoxColor
        box.Thickness = espSettings.BoxThickness
        box.Filled = false
        box.Transparency = 1

        local outline = Drawing.new("Square")
        outline.Visible = false
        outline.Color = Color3.fromRGB(0, 0, 0)
        outline.Thickness = espSettings.BoxThickness + 2
        outline.Filled = false
        outline.Transparency = 0.5

        local nameText = Drawing.new("Text")
        nameText.Visible = false
        nameText.Color = espSettings.NameColor
        nameText.Size = 14
        nameText.Center = true
        nameText.Outline = true
        nameText.OutlineColor = Color3.fromRGB(0, 0, 0)
        nameText.Font = 0

        local healthBarOutline = Drawing.new("Square")
        healthBarOutline.Visible = false
        healthBarOutline.Color = Color3.fromRGB(0, 0, 0)
        healthBarOutline.Thickness = 1
        healthBarOutline.Filled = true
        healthBarOutline.Transparency = 0.5

        local healthBar = Drawing.new("Square")
        healthBar.Visible = false
        healthBar.Color = espSettings.HealthColor
        healthBar.Thickness = 1
        healthBar.Filled = true
        healthBar.Transparency = 1

        -- Skeleton lines.
        local bones = {}
        for i = 1, #skeletonJoints do
            local line = Drawing.new("Line")
            line.Visible = false
            line.Color = espSettings.SkeletonColor
            line.Thickness = 1.5
            line.Transparency = 1
            bones[i] = line
        end

        espObjects[player] = {
            box = box,
            outline = outline,
            name = nameText,
            healthBar = healthBar,
            healthBarOutline = healthBarOutline,
            bones = bones,
        }
    end

    local function removeESP(player)
        local esp = espObjects[player]
        if not esp then return end
        for key, drawing in pairs(esp) do
            if key == "bones" then
                for _, bone in ipairs(drawing) do
                    bone:Remove()
                end
            else
                drawing:Remove()
            end
        end
        espObjects[player] = nil
    end

    local function updateESP()
        for player, esp in pairs(espObjects) do
            if not espSettings.Enabled then
                hideESPDrawings(esp)
                continue
            end

            local character = player.Character
            local humanoid = character and character:FindFirstChild("Humanoid")
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")

            if not character or not humanoid or not rootPart or not head or humanoid.Health <= 0 then
                hideESPDrawings(esp)
                continue
            end

            local rootPos, rootOnScreen = camera:WorldToViewportPoint(rootPart.Position)
            local headPos = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
            local legPos = camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))

            local distance = (camera.CFrame.Position - rootPart.Position).Magnitude

            if not rootOnScreen or distance > espSettings.MaxDistance then
                hideESPDrawings(esp)
                continue
            end

            -- Calculate box dimensions from head to feet.
            local boxHeight = math.abs(headPos.Y - legPos.Y)
            local boxWidth = boxHeight * 0.55

            local boxX = rootPos.X - boxWidth / 2
            local boxY = headPos.Y

            -- Box outline (black behind).
            esp.outline.Size = Vector2.new(boxWidth, boxHeight)
            esp.outline.Position = Vector2.new(boxX, boxY)
            esp.outline.Thickness = espSettings.BoxThickness + 2
            esp.outline.Visible = espSettings.ShowBox

            -- Main box.
            esp.box.Size = Vector2.new(boxWidth, boxHeight)
            esp.box.Position = Vector2.new(boxX, boxY)
            esp.box.Color = espSettings.BoxColor
            esp.box.Thickness = espSettings.BoxThickness
            esp.box.Visible = espSettings.ShowBox

            -- Name + distance text above box.
            if espSettings.ShowNames or espSettings.ShowDistance then
                local label = ""
                if espSettings.ShowNames then
                    label = espSettings.NameType == "Username" and player.Name or player.DisplayName
                end
                if espSettings.ShowDistance then
                    label = label .. (label ~= "" and " " or "") .. "[" .. math.floor(distance) .. "m]"
                end
                esp.name.Text = label
                esp.name.Size = espSettings.FontSize
                esp.name.Position = Vector2.new(rootPos.X, boxY - espSettings.FontSize - 2)
                esp.name.Color = espSettings.NameColor
                esp.name.Visible = true
            else
                esp.name.Visible = false
            end

            -- Skeleton ESP.
            if esp.bones then
                for i, joint in ipairs(skeletonJoints) do
                    local bone = esp.bones[i]
                    if espSettings.ShowSkeleton then
                        local partA = character:FindFirstChild(joint[1])
                        local partB = character:FindFirstChild(joint[2])
                        if partA and partB then
                            local posA, onA = camera:WorldToViewportPoint(partA.Position)
                            local posB, onB = camera:WorldToViewportPoint(partB.Position)
                            if onA and onB then
                                bone.From = Vector2.new(posA.X, posA.Y)
                                bone.To = Vector2.new(posB.X, posB.Y)
                                bone.Color = espSettings.SkeletonColor
                                bone.Visible = true
                            else
                                bone.Visible = false
                            end
                        else
                            bone.Visible = false
                        end
                    else
                        bone.Visible = false
                    end
                end
            end

            -- Health bar (left side of box).
            if espSettings.ShowHealth then
                local healthFraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                local barWidth = 3
                local barHeight = boxHeight * healthFraction

                -- Outline.
                esp.healthBarOutline.Size = Vector2.new(barWidth + 2, boxHeight + 2)
                esp.healthBarOutline.Position = Vector2.new(boxX - barWidth - 4, boxY - 1)
                esp.healthBarOutline.Visible = true

                -- Fill.
                esp.healthBar.Size = Vector2.new(barWidth, barHeight)
                esp.healthBar.Position = Vector2.new(boxX - barWidth - 3, boxY + (boxHeight - barHeight))
                esp.healthBar.Color = Color3.fromRGB(
                    255 * (1 - healthFraction),
                    255 * healthFraction,
                    0
                )
                esp.healthBar.Visible = true
            else
                esp.healthBar.Visible = false
                esp.healthBarOutline.Visible = false
            end
        end
    end

    -- Create ESP for existing players.
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            createESP(player)
        end
    end

    players.PlayerAdded:Connect(function(player)
        createESP(player)
    end)

    players.PlayerRemoving:Connect(function(player)
        removeESP(player)
    end)

    runService.RenderStepped:Connect(updateESP)

    -- ============================================================
    -- CONTAINER / LOOT ESP
    -- ============================================================

    local containerESPSettings = {
        Enabled = false,
        MaxDistance = 500,
        ShowDistance = false,
        Color = Color3.fromRGB(255, 200, 50),
        FontSize = 13,
    }

    -- All known container types with individual toggles (all ON by default).
    local containerTypes = {
        "SportBag", "Toolbox", "SmallMilitaryBox", "SmallShippingCrate",
        "PC", "SatchelBag", "MilitaryCrate", "ModificationStation",
        "LargeShippingCrate", "MedBag", "LargeABPOPABox", "LargeMilitaryBox",
        "GrenadeCrate", "HiddenCache", "FilingCabinet", "Fridge",
        "CashRegister", "KGBBag",
    }
    local containerTypeEnabled = {}
    for _, name in ipairs(containerTypes) do
        containerTypeEnabled[name] = true
    end

    local containerESPObjects = {} -- [Instance] = { text = Drawing }
    local containersFolder = workspace:FindFirstChild("Containers")

    local function isValidContainer(instance)
        -- Only top-level Models whose parent is the Containers folder (or a subfolder).
        if not instance:IsA("Model") then return false end
        -- Must have a name matching a known type, or be any Model directly in containers.
        return true
    end

    local function isContainerTypeAllowed(name)
        -- If the name is in our list, check the toggle. If unknown, always show.
        if containerTypeEnabled[name] ~= nil then
            return containerTypeEnabled[name]
        end
        return true
    end

    local function createContainerESP(container)
        if containerESPObjects[container] then return end
        if not isValidContainer(container) then return end

        local text = Drawing.new("Text")
        text.Visible = false
        text.Color = containerESPSettings.Color
        text.Size = containerESPSettings.FontSize
        text.Center = true
        text.Outline = true
        text.OutlineColor = Color3.fromRGB(0, 0, 0)
        text.Font = 0

        containerESPObjects[container] = { text = text }
    end

    local function removeContainerESP(container)
        local esp = containerESPObjects[container]
        if not esp then return end
        esp.text:Remove()
        containerESPObjects[container] = nil
    end

    local _containerScanTick = 0

    local function updateContainerESP()
        if not containerESPSettings.Enabled then
            for _, esp in pairs(containerESPObjects) do
                esp.text.Visible = false
            end
            return
        end

        _containerScanTick = _containerScanTick + 1

        -- Clean up destroyed containers.
        local deadContainers = {}
        for container in pairs(containerESPObjects) do
            if not container.Parent then table.insert(deadContainers, container) end
        end
        for _, container in ipairs(deadContainers) do
            containerESPObjects[container].text:Remove()
            containerESPObjects[container] = nil
        end

        -- Scan for new containers periodically (listeners handle most adds).
        if _containerScanTick % 60 == 0 and containersFolder then
            for _, child in ipairs(containersFolder:GetChildren()) do
                createContainerESP(child)
                if child:IsA("Folder") or child:IsA("Model") then
                    for _, sub in ipairs(child:GetChildren()) do
                        createContainerESP(sub)
                    end
                end
            end
        end

        -- Update visuals.
        for container, esp in pairs(containerESPObjects) do
            -- Check type filter.
            if not isContainerTypeAllowed(container.Name) then
                esp.text.Visible = false
                continue
            end

            local pos
            local primary = container.PrimaryPart or container:FindFirstChildWhichIsA("BasePart")
            pos = primary and primary.Position

            if not pos then
                esp.text.Visible = false
                continue
            end

            local screenPos, onScreen = camera:WorldToViewportPoint(pos)
            local distance = (camera.CFrame.Position - pos).Magnitude

            if not onScreen or distance > containerESPSettings.MaxDistance then
                esp.text.Visible = false
                continue
            end

            local label = container.Name
            if containerESPSettings.ShowDistance then
                label = label .. " [" .. math.floor(distance) .. "m]"
            end
            esp.text.Text = label
            esp.text.Position = Vector2.new(screenPos.X, screenPos.Y)
            esp.text.Color = containerESPSettings.Color
            esp.text.Size = containerESPSettings.FontSize
            esp.text.Visible = true
        end
    end

    -- Listen for new containers.
    if containersFolder then
        containersFolder.DescendantAdded:Connect(function(desc)
            createContainerESP(desc)
        end)
        containersFolder.DescendantRemoving:Connect(function(desc)
            removeContainerESP(desc)
        end)
        for _, child in ipairs(containersFolder:GetChildren()) do
            createContainerESP(child)
            if child:IsA("Folder") or child:IsA("Model") then
                for _, sub in ipairs(child:GetChildren()) do
                    createContainerESP(sub)
                end
            end
        end
    end

    runService.RenderStepped:Connect(updateContainerESP)

    -- ============================================================
    -- EXIT ESP
    -- ============================================================

    local exitESPSettings = {
        Enabled = false,
        MaxDistance = 1000,
        Color = Color3.fromRGB(0, 255, 100),
        FontSize = 14,
    }

    local exitESPObjects = {} -- [Instance] = { text = Drawing }
    local exitLocationsFolder = nil
    pcall(function()
        local noCollision = workspace:FindFirstChild("NoCollision")
        if noCollision then
            exitLocationsFolder = noCollision:FindFirstChild("ExitLocations")
        end
    end)

    local function createExitESP(exit)
        if exitESPObjects[exit] then return end
        if not exit:IsA("BasePart") and not exit:IsA("Model") then return end

        local text = Drawing.new("Text")
        text.Visible = false
        text.Color = exitESPSettings.Color
        text.Size = exitESPSettings.FontSize
        text.Center = true
        text.Outline = true
        text.OutlineColor = Color3.fromRGB(0, 0, 0)
        text.Font = 0

        exitESPObjects[exit] = { text = text }
    end

    local function removeExitESP(exit)
        local esp = exitESPObjects[exit]
        if not esp then return end
        esp.text:Remove()
        exitESPObjects[exit] = nil
    end

    local _exitScanTick = 0

    local function updateExitESP()
        if not exitESPSettings.Enabled then
            for _, esp in pairs(exitESPObjects) do
                esp.text.Visible = false
            end
            return
        end

        _exitScanTick = _exitScanTick + 1

        -- Clean up destroyed exits.
        local dead = {}
        for exit in pairs(exitESPObjects) do
            if not exit.Parent then table.insert(dead, exit) end
        end
        for _, exit in ipairs(dead) do
            exitESPObjects[exit].text:Remove()
            exitESPObjects[exit] = nil
        end

        -- Scan for new exits periodically (listeners handle most adds).
        if _exitScanTick % 60 == 0 and exitLocationsFolder then
            for _, child in ipairs(exitLocationsFolder:GetChildren()) do
                createExitESP(child)
            end
        end

        -- Update visuals.
        for exit, esp in pairs(exitESPObjects) do
            local pos
            if exit:IsA("Model") then
                local primary = exit.PrimaryPart or exit:FindFirstChildWhichIsA("BasePart")
                pos = primary and primary.Position
            elseif exit:IsA("BasePart") then
                pos = exit.Position
            end

            if not pos then
                esp.text.Visible = false
                continue
            end

            local screenPos, onScreen = camera:WorldToViewportPoint(pos)
            local distance = (camera.CFrame.Position - pos).Magnitude

            if not onScreen or distance > exitESPSettings.MaxDistance then
                esp.text.Visible = false
                continue
            end

            esp.text.Text = "EXIT [" .. math.floor(distance) .. "m]"
            esp.text.Position = Vector2.new(screenPos.X, screenPos.Y)
            esp.text.Color = exitESPSettings.Color
            esp.text.Size = exitESPSettings.FontSize
            esp.text.Visible = true
        end
    end

    if exitLocationsFolder then
        pcall(function()
            exitLocationsFolder.ChildAdded:Connect(function(child)
                createExitESP(child)
            end)
        end)
        for _, child in ipairs(exitLocationsFolder:GetChildren()) do
            createExitESP(child)
        end
    end

    runService.RenderStepped:Connect(updateExitESP)

    -- ============================================================
    -- CORPSE ESP (workspace.DroppedItems.<playerName>)
    -- ============================================================

    local corpseESPSettings = {
        Enabled = false,
        Color = Color3.fromRGB(255, 80, 80),
        ShowDistance = true,
        MaxDistance = 500,
        FontSize = 14,
    }

    local corpseESPObjects = {} -- [model] = { text = Drawing }
    local droppedItemsFolder = workspace:FindFirstChild("DroppedItems")

    local function isCorpseModel(model)
        if not model:IsA("Model") then return false end
        -- Corpses have body parts like Head, Torso, or HumanoidRootPart.
        return model:FindFirstChild("Head") or model:FindFirstChild("Torso")
            or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
    end

    local function createCorpseESP(model)
        if corpseESPObjects[model] then return end
        if not isCorpseModel(model) then return end

        local text = Drawing.new("Text")
        text.Visible = false
        text.Center = true
        text.Outline = true
        text.OutlineColor = Color3.fromRGB(0, 0, 0)
        text.Font = 0
        text.Size = corpseESPSettings.FontSize
        text.Color = corpseESPSettings.Color

        corpseESPObjects[model] = { text = text }
    end

    local function removeCorpseESP(model)
        local esp = corpseESPObjects[model]
        if not esp then return end
        esp.text:Remove()
        corpseESPObjects[model] = nil
    end

    local _corpseScanTick = 0

    local function updateCorpseESP()
        if not corpseESPSettings.Enabled then
            for _, esp in pairs(corpseESPObjects) do
                esp.text.Visible = false
            end
            return
        end

        _corpseScanTick = _corpseScanTick + 1

        -- Clean up destroyed corpses.
        local dead = {}
        for model in pairs(corpseESPObjects) do
            if not model.Parent then table.insert(dead, model) end
        end
        for _, model in ipairs(dead) do
            corpseESPObjects[model].text:Remove()
            corpseESPObjects[model] = nil
        end

        -- Scan DroppedItems periodically (listeners handle most adds).
        if _corpseScanTick % 60 == 0 and droppedItemsFolder then
            for _, playerFolder in ipairs(droppedItemsFolder:GetChildren()) do
                if playerFolder:IsA("Folder") or playerFolder:IsA("Model") then
                    for _, child in ipairs(playerFolder:GetChildren()) do
                        if child:IsA("Model") then
                            createCorpseESP(child)
                        end
                    end
                end
            end
        end

        -- Update visuals.
        for model, esp in pairs(corpseESPObjects) do
            local pos
            local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            if primary then
                pos = primary.Position
            end

            if not pos then
                esp.text.Visible = false
                continue
            end

            local screenPos, onScreen = camera:WorldToViewportPoint(pos)
            local distance = (camera.CFrame.Position - pos).Magnitude

            if not onScreen or distance > corpseESPSettings.MaxDistance then
                esp.text.Visible = false
                continue
            end

            local label = "Corpse"
            if corpseESPSettings.ShowDistance then
                label = label .. " [" .. math.floor(distance) .. "m]"
            end

            esp.text.Text = label
            esp.text.Position = Vector2.new(screenPos.X, screenPos.Y)
            esp.text.Color = corpseESPSettings.Color
            esp.text.Size = corpseESPSettings.FontSize
            esp.text.Visible = true
        end
    end

    -- Watch for new player folders in DroppedItems.
    if droppedItemsFolder then
        pcall(function()
            droppedItemsFolder.DescendantAdded:Connect(function(desc)
                if desc:IsA("Model") then
                    -- Delay slightly so children are loaded before checking.
                    task.defer(function() createCorpseESP(desc) end)
                end
            end)
        end)
    end

    runService.RenderStepped:Connect(updateCorpseESP)

    -- ============================================================
    -- EXPLOSIVE ESP (Mines = workspace.PMN2, Claymores = workspace.MON50)
    -- ============================================================

    local explosiveESPSettings = {
        Enabled = false,
        ShowMines = true,
        ShowClaymores = true,
        MaxDistance = 100,
        MineColor = Color3.fromRGB(255, 50, 50),
        ClaymoreColor = Color3.fromRGB(255, 165, 0),
        FontSize = 13,
    }

    local explosiveESPObjects = {} -- [Instance] = { text = Drawing }

    local function createExplosiveESP(instance)
        if explosiveESPObjects[instance] then return end
        if not instance:IsA("BasePart") and not instance:IsA("Model") then return end

        local text = Drawing.new("Text")
        text.Visible = false
        text.Size = explosiveESPSettings.FontSize
        text.Center = true
        text.Outline = true
        text.OutlineColor = Color3.fromRGB(0, 0, 0)
        text.Font = 0

        explosiveESPObjects[instance] = { text = text }
    end

    local function removeExplosiveESP(instance)
        local esp = explosiveESPObjects[instance]
        if not esp then return end
        esp.text:Remove()
        explosiveESPObjects[instance] = nil
    end

    local function getExplosiveType(instance)
        -- Check the instance itself and all ancestors for PMN2/MON50.
        local current = instance
        while current and current ~= workspace do
            if current.Name == "PMN2" then return "Mine" end
            if current.Name == "MON50" then return "Claymore" end
            current = current.Parent
        end
        return nil
    end

    local function isExplosiveRoot(instance)
        return instance.Name == "PMN2" or instance.Name == "MON50"
    end

    local function tryAddExplosive(instance)
        if not (instance:IsA("BasePart") or instance:IsA("Model")) then return end
        if isExplosiveRoot(instance) then
            createExplosiveESP(instance)
            return
        end
        if getExplosiveType(instance) then
            createExplosiveESP(instance)
        end
    end

    local _explosiveScanTick = 0

    local function updateExplosiveESP()
        if not explosiveESPSettings.Enabled then
            for _, esp in pairs(explosiveESPObjects) do
                esp.text.Visible = false
            end
            return
        end

        _explosiveScanTick = _explosiveScanTick + 1

        -- Clean up destroyed explosives.
        local dead = {}
        for inst in pairs(explosiveESPObjects) do
            if not inst.Parent then table.insert(dead, inst) end
        end
        for _, inst in ipairs(dead) do
            explosiveESPObjects[inst].text:Remove()
            explosiveESPObjects[inst] = nil
        end

        -- Full workspace scan periodically for any PMN2/MON50 anywhere.
        if _explosiveScanTick % 120 == 0 then
            for _, desc in ipairs(workspace:GetDescendants()) do
                if (desc:IsA("BasePart") or desc:IsA("Model")) and isExplosiveRoot(desc) then
                    createExplosiveESP(desc)
                end
            end
        end

        -- Update visuals.
        for inst, esp in pairs(explosiveESPObjects) do
            local expType = getExplosiveType(inst)
            if not expType then
                esp.text.Visible = false
                continue
            end

            -- Filter by type toggle.
            if expType == "Mine" and not explosiveESPSettings.ShowMines then
                esp.text.Visible = false
                continue
            end
            if expType == "Claymore" and not explosiveESPSettings.ShowClaymores then
                esp.text.Visible = false
                continue
            end

            local pos
            if inst:IsA("Model") then
                local primary = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                pos = primary and primary.Position
            elseif inst:IsA("BasePart") then
                pos = inst.Position
            end

            if not pos then
                esp.text.Visible = false
                continue
            end

            local screenPos, onScreen = camera:WorldToViewportPoint(pos)
            local distance = (camera.CFrame.Position - pos).Magnitude

            if not onScreen or distance > explosiveESPSettings.MaxDistance then
                esp.text.Visible = false
                continue
            end

            local color = expType == "Mine" and explosiveESPSettings.MineColor or explosiveESPSettings.ClaymoreColor
            esp.text.Text = expType .. " [" .. math.floor(distance) .. "m]"
            esp.text.Position = Vector2.new(screenPos.X, screenPos.Y)
            esp.text.Color = color
            esp.text.Size = explosiveESPSettings.FontSize
            esp.text.Visible = true
        end
    end

    -- Initial scan: find all PMN2/MON50 anywhere in workspace.
    for _, desc in ipairs(workspace:GetDescendants()) do
        if (desc:IsA("BasePart") or desc:IsA("Model")) and isExplosiveRoot(desc) then
            createExplosiveESP(desc)
        end
    end

    -- Listen globally for new instances anywhere in workspace.
    workspace.DescendantAdded:Connect(function(desc)
        if (desc:IsA("BasePart") or desc:IsA("Model")) and isExplosiveRoot(desc) then
            createExplosiveESP(desc)
        end
    end)
    workspace.DescendantRemoving:Connect(function(desc)
        removeExplosiveESP(desc)
    end)

    runService.RenderStepped:Connect(updateExplosiveESP)

    -- ============================================================
    -- NPC ESP (same features as Player ESP, targets workspace.AiZones)
    -- ============================================================

    local npcESPSettings = {
        Enabled = false,
        ShowBox = true,
        ShowNames = true,
        ShowHealth = true,
        ShowDistance = true,
        ShowSkeleton = false,
        BoxColor = Color3.fromRGB(255, 165, 0),
        NameColor = Color3.fromRGB(255, 255, 255),
        SkeletonColor = Color3.fromRGB(255, 165, 0),
        MaxDistance = 500,
        BoxThickness = 1.5,
        FontSize = 14,
    }

    local npcESPObjects = {} -- [npcModel] = { box, outline, name, healthBar, healthBarOutline, bones }
    local cachedNPCSet = {} -- Cached set of NPC models for efficient targeting

    local function createNPCESP(npc)
        if npcESPObjects[npc] then return end
        if not npc:IsA("Model") or not npc:FindFirstChildOfClass("Humanoid") then return end

        local box = Drawing.new("Square")
        box.Visible = false; box.Color = npcESPSettings.BoxColor
        box.Thickness = npcESPSettings.BoxThickness; box.Filled = false; box.Transparency = 1

        local outline = Drawing.new("Square")
        outline.Visible = false; outline.Color = Color3.fromRGB(0, 0, 0)
        outline.Thickness = npcESPSettings.BoxThickness + 2; outline.Filled = false; outline.Transparency = 0.5

        local nameText = Drawing.new("Text")
        nameText.Visible = false; nameText.Color = npcESPSettings.NameColor
        nameText.Size = 14; nameText.Center = true; nameText.Outline = true
        nameText.OutlineColor = Color3.fromRGB(0, 0, 0); nameText.Font = 0

        local healthBarOutline = Drawing.new("Square")
        healthBarOutline.Visible = false; healthBarOutline.Color = Color3.fromRGB(0, 0, 0)
        healthBarOutline.Thickness = 1; healthBarOutline.Filled = true; healthBarOutline.Transparency = 0.5

        local healthBar = Drawing.new("Square")
        healthBar.Visible = false; healthBar.Color = Color3.fromRGB(0, 255, 0)
        healthBar.Thickness = 1; healthBar.Filled = true; healthBar.Transparency = 1

        local bones = {}
        for i = 1, #skeletonJoints do
            local line = Drawing.new("Line")
            line.Visible = false; line.Color = npcESPSettings.SkeletonColor
            line.Thickness = 1.5; line.Transparency = 1
            bones[i] = line
        end

        npcESPObjects[npc] = {
            box = box, outline = outline, name = nameText,
            healthBar = healthBar, healthBarOutline = healthBarOutline, bones = bones,
        }
    end

    local function removeNPCESP(npc)
        local esp = npcESPObjects[npc]
        if not esp then return end
        for key, drawing in pairs(esp) do
            if key == "bones" then
                for _, bone in ipairs(drawing) do bone:Remove() end
            else
                drawing:Remove()
            end
        end
        npcESPObjects[npc] = nil
    end

    local _npcScanTick = 0

    local function updateNPCESP()
        _npcScanTick = _npcScanTick + 1

        -- Clean up destroyed NPCs (collect first to avoid modifying during iteration).
        local deadNPCs = {}
        for npc in pairs(npcESPObjects) do
            if not npc.Parent then table.insert(deadNPCs, npc) end
        end
        for _, npc in ipairs(deadNPCs) do
            cachedNPCSet[npc] = nil
            removeNPCESP(npc)
        end

        -- Scan for new NPCs periodically (listeners handle most adds).
        if _npcScanTick % 60 == 0 then
            local aiFolder = workspace:FindFirstChild("AiZones")
            if aiFolder then
                for _, desc in ipairs(aiFolder:GetDescendants()) do
                    if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") and not npcESPObjects[desc] then
                        cachedNPCSet[desc] = true
                        createNPCESP(desc)
                    end
                end
            end
        end

        for npc, esp in pairs(npcESPObjects) do
            if not npcESPSettings.Enabled then
                hideESPDrawings(esp)
                continue
            end

            local humanoid = npc:FindFirstChildOfClass("Humanoid")
            local rootPart = npc:FindFirstChild("HumanoidRootPart")
            local head = npc:FindFirstChild("Head")

            if not humanoid or not rootPart or not head or humanoid.Health <= 0 then
                hideESPDrawings(esp)
                continue
            end

            local rootPos, rootOnScreen = camera:WorldToViewportPoint(rootPart.Position)
            local headPos = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
            local legPos = camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
            local distance = (camera.CFrame.Position - rootPart.Position).Magnitude

            if not rootOnScreen or distance > npcESPSettings.MaxDistance then
                hideESPDrawings(esp)
                continue
            end

            local boxHeight = math.abs(headPos.Y - legPos.Y)
            local boxWidth = boxHeight * 0.55
            local boxX = rootPos.X - boxWidth / 2
            local boxY = headPos.Y

            esp.outline.Size = Vector2.new(boxWidth, boxHeight)
            esp.outline.Position = Vector2.new(boxX, boxY)
            esp.outline.Thickness = npcESPSettings.BoxThickness + 2
            esp.outline.Visible = npcESPSettings.ShowBox

            esp.box.Size = Vector2.new(boxWidth, boxHeight)
            esp.box.Position = Vector2.new(boxX, boxY)
            esp.box.Color = npcESPSettings.BoxColor
            esp.box.Thickness = npcESPSettings.BoxThickness
            esp.box.Visible = npcESPSettings.ShowBox

            if npcESPSettings.ShowNames or npcESPSettings.ShowDistance then
                local label = ""
                if npcESPSettings.ShowNames then label = npc.Name end
                if npcESPSettings.ShowDistance then
                    label = label .. (label ~= "" and " " or "") .. "[" .. math.floor(distance) .. "m]"
                end
                esp.name.Text = label
                esp.name.Size = npcESPSettings.FontSize
                esp.name.Position = Vector2.new(rootPos.X, boxY - npcESPSettings.FontSize - 2)
                esp.name.Color = npcESPSettings.NameColor
                esp.name.Visible = true
            else esp.name.Visible = false end

            if esp.bones then
                for i, joint in ipairs(skeletonJoints) do
                    local bone = esp.bones[i]
                    if npcESPSettings.ShowSkeleton then
                        local partA = npc:FindFirstChild(joint[1])
                        local partB = npc:FindFirstChild(joint[2])
                        if partA and partB then
                            local posA, onA = camera:WorldToViewportPoint(partA.Position)
                            local posB, onB = camera:WorldToViewportPoint(partB.Position)
                            if onA and onB then
                                bone.From = Vector2.new(posA.X, posA.Y)
                                bone.To = Vector2.new(posB.X, posB.Y)
                                bone.Color = npcESPSettings.SkeletonColor
                                bone.Visible = true
                            else bone.Visible = false end
                        else bone.Visible = false end
                    else bone.Visible = false end
                end
            end

            if npcESPSettings.ShowHealth then
                local healthFraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                local barWidth = 3
                local barHeight = boxHeight * healthFraction
                esp.healthBarOutline.Size = Vector2.new(barWidth + 2, boxHeight + 2)
                esp.healthBarOutline.Position = Vector2.new(boxX - barWidth - 4, boxY - 1)
                esp.healthBarOutline.Visible = true
                esp.healthBar.Size = Vector2.new(barWidth, barHeight)
                esp.healthBar.Position = Vector2.new(boxX - barWidth - 3, boxY + (boxHeight - barHeight))
                esp.healthBar.Color = Color3.fromRGB(255 * (1 - healthFraction), 255 * healthFraction, 0)
                esp.healthBar.Visible = true
            else
                esp.healthBar.Visible = false
                esp.healthBarOutline.Visible = false
            end
        end
    end

    -- Listen for new NPCs and maintain cached set.
    local npcAiFolder = workspace:FindFirstChild("AiZones")
    if npcAiFolder then
        npcAiFolder.DescendantAdded:Connect(function(desc)
            if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") then
                cachedNPCSet[desc] = true
                createNPCESP(desc)
            end
        end)
        npcAiFolder.DescendantRemoving:Connect(function(desc)
            cachedNPCSet[desc] = nil
            removeNPCESP(desc)
        end)
        for _, desc in ipairs(npcAiFolder:GetDescendants()) do
            if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") then
                cachedNPCSet[desc] = true
            end
        end
    end

    runService.RenderStepped:Connect(updateNPCESP)

    -- Visuals tab UI.
    local ESPGroup = Tabs.Visuals:AddLeftGroupbox("ESP")

    ESPGroup:AddToggle("ESPEnabled", {
        Text = "Enable ESP",
        Default = false,
        Callback = function(value)
            espSettings.Enabled = value
        end,
    })

    ESPGroup:AddToggle("ESPBox", {
        Text = "Show Box",
        Default = true,
        Callback = function(value)
            espSettings.ShowBox = value
        end,
    }):AddColorPicker("ESPBoxColor", {
        Default = Color3.fromRGB(255, 50, 50),
    })

    ESPGroup:AddToggle("ESPSkeleton", {
        Text = "Show Skeleton",
        Default = false,
        Callback = function(value)
            espSettings.ShowSkeleton = value
        end,
    }):AddColorPicker("ESPSkeletonColor", {
        Default = Color3.fromRGB(255, 255, 255),
    })

    ESPGroup:AddToggle("ESPNames", {
        Text = "Show Names",
        Default = true,
        Callback = function(value)
            espSettings.ShowNames = value
        end,
    }):AddColorPicker("ESPNameColor", {
        Default = Color3.fromRGB(255, 255, 255),
    })

    ESPGroup:AddToggle("ESPHealth", {
        Text = "Show Health Bar",
        Default = true,
        Callback = function(value)
            espSettings.ShowHealth = value
        end,
    })

    ESPGroup:AddDropdown("ESPNameType", {
        Text = "Name Type",
        Values = { "Display Name", "Username" },
        Default = 1,
        Callback = function(value)
            espSettings.NameType = value
        end,
    })

    ESPGroup:AddToggle("ESPDistance", {
        Text = "Show Distance",
        Default = true,
        Callback = function(value)
            espSettings.ShowDistance = value
        end,
    })

    ESPGroup:AddSlider("ESPMaxDist", {
        Text = "Max Distance",
        Default = 1000,
        Min = 100,
        Max = 5000,
        Rounding = 0,
        Callback = function(value)
            espSettings.MaxDistance = value
        end,
    })

    Options.ESPBoxColor:OnChanged(function()
        espSettings.BoxColor = Options.ESPBoxColor.Value
    end)

    Options.ESPNameColor:OnChanged(function()
        espSettings.NameColor = Options.ESPNameColor.Value
    end)

    Options.ESPSkeletonColor:OnChanged(function()
        espSettings.SkeletonColor = Options.ESPSkeletonColor.Value
    end)

    ESPGroup:AddSlider("ESPFontSize", {
        Text = "Font Size",
        Default = 14,
        Min = 10,
        Max = 24,
        Rounding = 0,
        Callback = function(value)
            espSettings.FontSize = value
        end,
    })

    -- Container ESP UI.
    local ContainerGroup = Tabs.Visuals:AddRightGroupbox("Container ESP")

    ContainerGroup:AddToggle("ContainerESP", {
        Text = "Enable Container ESP",
        Default = false,
        Callback = function(value)
            containerESPSettings.Enabled = value
        end,
    }):AddColorPicker("ContainerColor", {
        Default = Color3.fromRGB(255, 200, 50),
    })

    Options.ContainerColor:OnChanged(function()
        containerESPSettings.Color = Options.ContainerColor.Value
    end)

    ContainerGroup:AddToggle("ContainerShowDist", {
        Text = "Show Distance",
        Default = false,
        Callback = function(value)
            containerESPSettings.ShowDistance = value
        end,
    })

    ContainerGroup:AddSlider("ContainerMaxDist", {
        Text = "Max Distance",
        Default = 500,
        Min = 50,
        Max = 2000,
        Rounding = 0,
        Callback = function(value)
            containerESPSettings.MaxDistance = value
        end,
    })

    ContainerGroup:AddDivider()

    -- Per-type toggles.
    local containerTypeNames = {
        {id = "CT_MilitaryCrate",       name = "MilitaryCrate"},
        {id = "CT_LargeMilitaryBox",    name = "LargeMilitaryBox"},
        {id = "CT_SmallMilitaryBox",    name = "SmallMilitaryBox"},
        {id = "CT_GrenadeCrate",        name = "GrenadeCrate"},
        {id = "CT_LargeShippingCrate",  name = "LargeShippingCrate"},
        {id = "CT_SmallShippingCrate",  name = "SmallShippingCrate"},
        {id = "CT_LargeABPOPABox",      name = "LargeABPOPABox"},
        {id = "CT_HiddenCache",         name = "HiddenCache"},
        {id = "CT_MedBag",              name = "MedBag"},
        {id = "CT_SportBag",            name = "SportBag"},
        {id = "CT_SatchelBag",          name = "SatchelBag"},
        {id = "CT_KGBBag",              name = "KGBBag"},
        {id = "CT_Toolbox",             name = "Toolbox"},
        {id = "CT_FilingCabinet",       name = "FilingCabinet"},
        {id = "CT_Fridge",              name = "Fridge"},
        {id = "CT_CashRegister",        name = "CashRegister"},
        {id = "CT_PC",                  name = "PC"},
        {id = "CT_ModStation",          name = "ModificationStation"},
    }

    for _, ct in ipairs(containerTypeNames) do
        ContainerGroup:AddToggle(ct.id, {
            Text = ct.name,
            Default = true,
            Callback = function(value)
                containerTypeEnabled[ct.name] = value
            end,
        })
    end

    -- Exit ESP UI.
    local ExitGroup = Tabs.Visuals:AddRightGroupbox("Exit ESP")

    ExitGroup:AddToggle("ExitESP", {
        Text = "Enable Exit ESP",
        Default = false,
        Callback = function(value)
            exitESPSettings.Enabled = value
        end,
    }):AddColorPicker("ExitColor", {
        Default = Color3.fromRGB(0, 255, 100),
    })

    Options.ExitColor:OnChanged(function()
        exitESPSettings.Color = Options.ExitColor.Value
    end)

    ExitGroup:AddSlider("ExitMaxDist", {
        Text = "Max Distance",
        Default = 1000,
        Min = 50,
        Max = 5000,
        Rounding = 0,
        Callback = function(value)
            exitESPSettings.MaxDistance = value
        end,
    })

    -- Corpse ESP UI.
    local CorpseGroup = Tabs.Visuals:AddRightGroupbox("Corpse ESP")

    CorpseGroup:AddToggle("CorpseESP", {
        Text = "Enable Corpse ESP",
        Default = false,
        Callback = function(value)
            corpseESPSettings.Enabled = value
        end,
    }):AddColorPicker("CorpseColor", {
        Default = Color3.fromRGB(255, 80, 80),
    })

    Options.CorpseColor:OnChanged(function()
        corpseESPSettings.Color = Options.CorpseColor.Value
    end)

    CorpseGroup:AddToggle("CorpseShowDist", {
        Text = "Show Distance",
        Default = true,
        Callback = function(value)
            corpseESPSettings.ShowDistance = value
        end,
    })

    CorpseGroup:AddSlider("CorpseMaxDist", {
        Text = "Max Distance",
        Default = 500,
        Min = 50,
        Max = 5000,
        Rounding = 0,
        Callback = function(value)
            corpseESPSettings.MaxDistance = value
        end,
    })

    -- Explosive ESP UI.
    local ExplosiveGroup = Tabs.Visuals:AddRightGroupbox("Explosive ESP")

    ExplosiveGroup:AddToggle("ExplosiveESP", {
        Text = "Enable Explosive ESP",
        Default = false,
        Callback = function(value)
            explosiveESPSettings.Enabled = value
        end,
    })

    ExplosiveGroup:AddToggle("ExplosiveMines", {
        Text = "Show Mines",
        Default = true,
        Callback = function(value)
            explosiveESPSettings.ShowMines = value
        end,
    }):AddColorPicker("MineColor", {
        Default = Color3.fromRGB(255, 50, 50),
    })

    ExplosiveGroup:AddToggle("ExplosiveClaymores", {
        Text = "Show Claymores",
        Default = true,
        Callback = function(value)
            explosiveESPSettings.ShowClaymores = value
        end,
    }):AddColorPicker("ClaymoreColor", {
        Default = Color3.fromRGB(255, 165, 0),
    })

    Options.MineColor:OnChanged(function()
        explosiveESPSettings.MineColor = Options.MineColor.Value
    end)

    Options.ClaymoreColor:OnChanged(function()
        explosiveESPSettings.ClaymoreColor = Options.ClaymoreColor.Value
    end)

    ExplosiveGroup:AddSlider("ExplosiveMaxDist", {
        Text = "Max Distance",
        Default = 100,
        Min = 10,
        Max = 500,
        Rounding = 0,
        Callback = function(value)
            explosiveESPSettings.MaxDistance = value
        end,
    })

    -- NPC ESP UI.
    local NPCESPGroup = Tabs.Visuals:AddLeftGroupbox("NPC ESP")

    NPCESPGroup:AddToggle("NPCESPEnabled", {
        Text = "Enable NPC ESP",
        Default = false,
        Callback = function(value)
            npcESPSettings.Enabled = value
        end,
    })

    NPCESPGroup:AddToggle("NPCESPBox", {
        Text = "Show Box",
        Default = true,
        Callback = function(value)
            npcESPSettings.ShowBox = value
        end,
    }):AddColorPicker("NPCESPBoxColor", {
        Default = Color3.fromRGB(255, 165, 0),
    })

    NPCESPGroup:AddToggle("NPCESPSkeleton", {
        Text = "Show Skeleton",
        Default = false,
        Callback = function(value)
            npcESPSettings.ShowSkeleton = value
        end,
    }):AddColorPicker("NPCESPSkeletonColor", {
        Default = Color3.fromRGB(255, 165, 0),
    })

    NPCESPGroup:AddToggle("NPCESPNames", {
        Text = "Show Names",
        Default = true,
        Callback = function(value)
            npcESPSettings.ShowNames = value
        end,
    }):AddColorPicker("NPCESPNameColor", {
        Default = Color3.fromRGB(255, 255, 255),
    })

    NPCESPGroup:AddToggle("NPCESPHealth", {
        Text = "Show Health Bar",
        Default = true,
        Callback = function(value)
            npcESPSettings.ShowHealth = value
        end,
    })

    NPCESPGroup:AddToggle("NPCESPDistance", {
        Text = "Show Distance",
        Default = true,
        Callback = function(value)
            npcESPSettings.ShowDistance = value
        end,
    })

    NPCESPGroup:AddSlider("NPCESPMaxDist", {
        Text = "Max Distance",
        Default = 500,
        Min = 50,
        Max = 2000,
        Rounding = 0,
        Callback = function(value)
            npcESPSettings.MaxDistance = value
        end,
    })

    Options.NPCESPBoxColor:OnChanged(function()
        npcESPSettings.BoxColor = Options.NPCESPBoxColor.Value
    end)

    Options.NPCESPNameColor:OnChanged(function()
        npcESPSettings.NameColor = Options.NPCESPNameColor.Value
    end)

    Options.NPCESPSkeletonColor:OnChanged(function()
        npcESPSettings.SkeletonColor = Options.NPCESPSkeletonColor.Value
    end)

    -- ============================================================
    -- FULLBRIGHT & NO FOG
    -- ============================================================

    local lighting = game:GetService("Lighting")

    -- Store originals to restore later.
    local origLighting = {
        Brightness = lighting.Brightness,
        ClockTime = lighting.ClockTime,
        FogEnd = lighting.FogEnd,
        FogStart = lighting.FogStart,
        GlobalShadows = lighting.GlobalShadows,
        Ambient = lighting.Ambient,
        OutdoorAmbient = lighting.OutdoorAmbient,
    }

    -- Track effects we disable so we can restore them.
    local disabledEffects = {}

    local function setFullbright(enabled)
        if enabled then
            lighting.Brightness = 2
            lighting.ClockTime = 14
            lighting.GlobalShadows = false
            lighting.Ambient = Color3.fromRGB(178, 178, 178)
            lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)

            -- Only disable effects that reduce visibility, NOT ColorCorrectionEffect.
            for _, effect in ipairs(lighting:GetChildren()) do
                if effect:IsA("BloomEffect") or effect:IsA("BlurEffect")
                    or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect") then
                    if effect.Enabled then
                        effect.Enabled = false
                        table.insert(disabledEffects, effect)
                    end
                elseif effect:IsA("Atmosphere") then
                    pcall(function()
                        if effect.Density > 0 then
                            local origDensity = effect.Density
                            effect.Density = 0
                            table.insert(disabledEffects, {effect = effect, type = "atmosphere", density = origDensity})
                        end
                    end)
                end
            end
        else
            lighting.Brightness = origLighting.Brightness
            lighting.ClockTime = origLighting.ClockTime
            lighting.GlobalShadows = origLighting.GlobalShadows
            lighting.Ambient = origLighting.Ambient
            lighting.OutdoorAmbient = origLighting.OutdoorAmbient

            for _, entry in ipairs(disabledEffects) do
                pcall(function()
                    if type(entry) == "table" and entry.type == "atmosphere" then
                        if entry.effect and entry.effect.Parent then
                            entry.effect.Density = entry.density
                        end
                    elseif typeof(entry) == "Instance" and entry.Parent then
                        entry.Enabled = true
                    end
                end)
            end
            disabledEffects = {}
        end
    end

    local function setNoFog(enabled)
        if enabled then
            lighting.FogEnd = 1e9
            lighting.FogStart = 1e9
        else
            lighting.FogEnd = origLighting.FogEnd
            lighting.FogStart = origLighting.FogStart
        end
    end

    local WorldGroup = Tabs.Visuals:AddRightGroupbox("World")

    WorldGroup:AddToggle("Fullbright", {
        Text = "Fullbright",
        Default = false,
        Callback = function(value)
            setFullbright(value)
        end,
    })

    WorldGroup:AddToggle("NoFog", {
        Text = "No Fog",
        Default = false,
        Callback = function(value)
            setNoFog(value)
        end,
    })

    local origGrassLength = 0.25
    pcall(function()
        if typeof(gethiddenproperty) == "function" then
            origGrassLength = gethiddenproperty(workspace.Terrain, "GrassLength") or 0.25
        end
    end)

    WorldGroup:AddToggle("NoGrass", {
        Text = "No Grass",
        Default = false,
        Callback = function(value)
            local terrain = workspace.Terrain
            if value then
                pcall(function() sethiddenproperty(terrain, "Decoration", false) end)
                pcall(function() sethiddenproperty(terrain, "GrassLength", 0) end)
            else
                pcall(function() sethiddenproperty(terrain, "Decoration", true) end)
                pcall(function() sethiddenproperty(terrain, "GrassLength", origGrassLength) end)
            end
        end,
    })

    -- ============================================================
    -- BULLET TRACERS
    -- ============================================================

    local tracerSettings = {
        Enabled = false,
        Color = Color3.fromRGB(255, 0, 0),
        HitTracer = true,
        HitColor = Color3.fromRGB(0, 255, 0),
        Thickness = 1.5,
        Duration = 0.5,
    }

    local activeTracers = {}

    -- Create a 3D tracer beam in the world that persists.
    local function drawTracer(origin, endpoint, isHit)
        if not tracerSettings.Enabled then return end

        local color = (isHit and tracerSettings.HitTracer) and tracerSettings.HitColor or tracerSettings.Color

        -- Create a thin part as the tracer line.
        local distance = (endpoint - origin).Magnitude
        local midpoint = (origin + endpoint) / 2

        local tracerPart = Instance.new("Part")
        tracerPart.Anchored = true
        tracerPart.CanCollide = false
        tracerPart.CanQuery = false
        tracerPart.CanTouch = false
        tracerPart.Material = Enum.Material.Neon
        tracerPart.Color = color
        tracerPart.Size = Vector3.new(tracerSettings.Thickness * 0.02, tracerSettings.Thickness * 0.02, distance)
        tracerPart.CFrame = CFrame.lookAt(midpoint, endpoint)
        tracerPart.Transparency = 0
        tracerPart.Parent = workspace

        table.insert(activeTracers, { part = tracerPart, created = tick(), isHit = isHit })
    end

    -- Clean up expired tracers + fade.
    runService.RenderStepped:Connect(function()
        local now = tick()
        for i = #activeTracers, 1, -1 do
            local t = activeTracers[i]
            local elapsed = now - t.created

            if elapsed >= tracerSettings.Duration then
                t.part:Destroy()
                table.remove(activeTracers, i)
            else
                t.part.Transparency = elapsed / tracerSettings.Duration
                if not t.isHit then
                    t.part.Color = tracerSettings.Color
                end
            end
        end
    end)

    -- Tracers are drawn when FireProjectile is detected in the namecall hook.
    -- Uses camera origin for accuracy and avoids going through the hook for raycast.
    function fireTracer(direction)
        if not tracerSettings.Enabled then return end
        if typeof(direction) ~= "Vector3" then return end

        local character = localPlayer.Character
        if not character then return end

        local origin = camera.CFrame.Position
        local dir = direction.Unit * 2000

        -- Raycast without going through the hook.
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = {character}

        local result = nil
        pcall(function()
            result = workspace.Raycast(workspace, origin, dir, rayParams)
        end)

        local endpoint = result and result.Position or (origin + dir)

        -- Check if the bullet hit a player.
        local isHit = false
        if result and result.Instance then
            local inst = result.Instance
            local model = inst:FindFirstAncestorOfClass("Model")
            if model then
                for _, p in ipairs(players:GetPlayers()) do
                    if p ~= localPlayer and p.Character == model then
                        isHit = true
                        break
                    end
                end
            end
        end

        drawTracer(origin, endpoint, isHit)
        dlog("Tracer drawn: hit=" .. tostring(isHit))
    end

    local TracerGroup = Tabs.Visuals:AddRightGroupbox("Bullet Tracers")

    TracerGroup:AddToggle("TracersEnabled", {
        Text = "Enable Tracers",
        Default = false,
        Callback = function(value)
            tracerSettings.Enabled = value
            if not value then
                for _, t in ipairs(activeTracers) do
                    t.part:Destroy()
                end
                activeTracers = {}
            end
        end,
    })

    TracerGroup:AddSlider("TracerDuration", {
        Text = "Duration",
        Default = 0.5,
        Min = 0.1,
        Max = 3.0,
        Rounding = 1,
        Suffix = "s",
        Callback = function(value)
            tracerSettings.Duration = value
        end,
    })

    TracerGroup:AddSlider("TracerThickness", {
        Text = "Thickness",
        Default = 1.5,
        Min = 0.5,
        Max = 5,
        Rounding = 1,
        Callback = function(value)
            tracerSettings.Thickness = value
        end,
    })

    TracerGroup:AddLabel("Tracer Color"):AddColorPicker("TracerColor", {
        Default = Color3.fromRGB(255, 0, 0),
    })

    Options.TracerColor:OnChanged(function()
        tracerSettings.Color = Options.TracerColor.Value
    end)

    TracerGroup:AddToggle("HitTracer", {
        Text = "Hit Tracer",
        Default = true,
        Callback = function(value)
            tracerSettings.HitTracer = value
        end,
    }):AddColorPicker("HitTracerColor", {
        Default = Color3.fromRGB(0, 255, 0),
    })

    Options.HitTracerColor:OnChanged(function()
        tracerSettings.HitColor = Options.HitTracerColor.Value
    end)

    -- ============================================================
    -- SNAPLINES (Silent Aim integration)
    -- ============================================================

    local snaplineSettings = {
        Enabled = false,
        Color = Color3.fromRGB(0, 255, 0),
    }

    local snapline = Drawing.new("Line")
    snapline.Visible = false
    snapline.Color = snaplineSettings.Color
    snapline.Thickness = 1.5
    snapline.Transparency = 1

    local SnapGroup = Tabs.Visuals:AddRightGroupbox("Snaplines")

    SnapGroup:AddToggle("SnaplineEnabled", {
        Text = "Enable Snaplines",
        Default = false,
        Callback = function(value)
            snaplineSettings.Enabled = value
            if not value then snapline.Visible = false end
        end,
    }):AddColorPicker("SnaplineColor", {
        Default = Color3.fromRGB(0, 255, 0),
    })

    Options.SnaplineColor:OnChanged(function()
        snaplineSettings.Color = Options.SnaplineColor.Value
    end)

    -- Helper: check if feature is active via toggle OR keybind (supports Hold/Always/Toggle modes).
    local function isFeatureActive(settingsEnabled, optionKey)
        if settingsEnabled then return true end
        if Options and Options[optionKey] and type(Options[optionKey].GetState) == "function" then
            local ok, state = pcall(Options[optionKey].GetState, Options[optionKey])
            if ok and state then return true end
        end
        return false
    end

    -- ============================================================
    -- SPEED
    -- ============================================================

    local speedSettings = {
        Enabled = false,
        Speed = 28,
        Method = "CFrame Burst",  -- "CFrame Burst", "CFrame Smooth", "State Spoof"
        BurstOn = 0.3,   -- seconds moving fast
        BurstOff = 0.15,  -- seconds pausing (server catch-up)
    }

    local speedConnection = nil
    local originalWalkSpeed = 16
    local burstTimer = 0
    local burstActive = true

    local function getMovementDirection()
        local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if not humanoid then return Vector3.zero end
        local moveDir = humanoid.MoveDirection
        if moveDir.Magnitude == 0 then return Vector3.zero end
        return moveDir.Unit
    end

    local function updateSpeed(dt)
        if not isFeatureActive(speedSettings.Enabled, "SpeedKey") then return end

        local character = localPlayer.Character
        if not character then return end

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")
        if not rootPart or not humanoid then return end

        local moveDir = getMovementDirection()
        if moveDir.Magnitude == 0 then
            burstTimer = 0
            burstActive = true
            return
        end

        local method = speedSettings.Method

        if method == "CFrame Burst" then
            -- Burst: move fast for a short window, then pause to let server catch up.
            burstTimer = burstTimer + dt

            if burstActive then
                -- Moving phase.
                local extraSpeed = speedSettings.Speed - humanoid.WalkSpeed
                if extraSpeed > 0 then
                    local offset = moveDir * extraSpeed * dt
                    rootPart.CFrame = rootPart.CFrame + Vector3.new(offset.X, 0, offset.Z)
                end
                if burstTimer >= speedSettings.BurstOn then
                    burstTimer = 0
                    burstActive = false
                end
            else
                -- Pause phase — only normal walkspeed moves you.
                if burstTimer >= speedSettings.BurstOff then
                    burstTimer = 0
                    burstActive = true
                end
            end

        elseif method == "CFrame Smooth" then
            -- Smooth: constant small CFrame nudges, keep speed low to stay under threshold.
            local extraSpeed = speedSettings.Speed - humanoid.WalkSpeed
            if extraSpeed > 0 then
                local offset = moveDir * extraSpeed * dt
                rootPart.CFrame = rootPart.CFrame + Vector3.new(offset.X, 0, offset.Z)
            end

        end
    end

    local function onSpeedToggle(enabled)
        speedSettings.Enabled = enabled
        burstTimer = 0
        burstActive = true
    end

    -- Cache original WalkSpeed on character spawn.
    localPlayer.CharacterAdded:Connect(function(char)
        local humanoid = char:WaitForChild("Humanoid", 10)
        if humanoid then
            originalWalkSpeed = humanoid.WalkSpeed
        end
    end)

    if localPlayer.Character then
        local humanoid = localPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            originalWalkSpeed = humanoid.WalkSpeed
        end
    end

    speedConnection = runService.RenderStepped:Connect(updateSpeed)

    -- Movement tab UI.
    local SpeedGroup = Tabs.Movement:AddLeftGroupbox("Speed")

    SpeedGroup:AddToggle("SpeedEnabled", {
        Text = "Enable Speed",
        Default = false,
        Callback = function(value) onSpeedToggle(value) end,
    }):AddKeyPicker("SpeedKey", {
        Default = "None",
        Text = "Speed",
        NoUI = false,
    })

    SpeedGroup:AddDropdown("SpeedMethod", {
        Text = "Method",
        Values = { "CFrame Burst", "CFrame Smooth" },
        Default = 1,
        Callback = function(value)
            speedSettings.Method = value
        end,
    })

    SpeedGroup:AddSlider("SpeedValue", {
        Text = "Speed",
        Default = 28,
        Min = 16,
        Max = 100,
        Rounding = 0,
        Suffix = " studs/s",
        Callback = function(value)
            speedSettings.Speed = value
        end,
    })

    SpeedGroup:AddDivider()

    SpeedGroup:AddSlider("BurstOn", {
        Text = "Burst Duration",
        Default = 0.3,
        Min = 0.1,
        Max = 1.0,
        Rounding = 2,
        Suffix = "s",
        Callback = function(value)
            speedSettings.BurstOn = value
        end,
    })

    SpeedGroup:AddSlider("BurstOff", {
        Text = "Pause Duration",
        Default = 0.15,
        Min = 0.05,
        Max = 0.5,
        Rounding = 2,
        Suffix = "s",
        Callback = function(value)
            speedSettings.BurstOff = value
        end,
    })

    SpeedGroup:AddLabel("Burst = move/pause cycles")
    SpeedGroup:AddLabel("Smooth = constant, keep low")

    -- ============================================================
    -- SPIDER (Wall Climb)
    -- ============================================================

    local spiderSettings = {
        Enabled = false,
        ClimbSpeed = 24,
    }

    local spiderConnection = nil
    local spiderRayParams = RaycastParams.new()
    spiderRayParams.FilterType = Enum.RaycastFilterType.Exclude

    spiderConnection = runService.RenderStepped:Connect(function(dt)
        if not isFeatureActive(spiderSettings.Enabled, "SpiderKey") then return end

        local character = localPlayer.Character
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")
        if not rootPart or not humanoid then return end

        -- Only activate when moving into a wall.
        local moveDir = humanoid.MoveDirection
        if moveDir.Magnitude == 0 then return end

        -- Raycast forward to detect walls.
        spiderRayParams.FilterDescendantsInstances = {character}

        local rayOrigin = rootPart.Position
        local rayDirection = moveDir.Unit * 3
        local result = workspace:Raycast(rayOrigin, rayDirection, spiderRayParams)

        if result then
            -- Wall detected — climb up.
            local wallNormal = result.Normal
            local isWall = math.abs(wallNormal.Y) < 0.3 -- Not a floor/ceiling.

            if isWall then
                rootPart.AssemblyLinearVelocity = Vector3.new(
                    rootPart.AssemblyLinearVelocity.X,
                    spiderSettings.ClimbSpeed,
                    rootPart.AssemblyLinearVelocity.Z
                )
            end
        end
    end)

    local SpiderGroup = Tabs.Movement:AddLeftGroupbox("Spiderman")

    SpiderGroup:AddToggle("SpiderEnabled", {
        Text = "Enable Spiderman",
        Default = false,
        Callback = function(value) spiderSettings.Enabled = value end,
    }):AddKeyPicker("SpiderKey", {
        Default = "None",
        Text = "Spiderman",
        NoUI = false,
    })

    SpiderGroup:AddSlider("SpiderSpeed", {
        Text = "Climb Speed",
        Default = 24,
        Min = 10,
        Max = 60,
        Rounding = 0,
        Suffix = " studs/s",
        Callback = function(value)
            spiderSettings.ClimbSpeed = value
        end,
    })

    SpiderGroup:AddLabel("Walk into walls to climb")
    SpiderGroup:AddLabel("Game has ladders = less sus")

    -- ============================================================
    -- NO JUMP COOLDOWN
    -- ============================================================

    local noJumpCDSettings = {
        Enabled = false,
        Bhop = false,
        Debug = false,
    }

    local noJumpCDConnection = nil
    local noJumpCDStateConn = nil
    local noJumpCDCharConn = nil
    local _jumpDiagCount = 0
    local _cachedJumpHeight = 0
    local _lastForceJump = 0

    local function setupJumpCD(humanoid)
        if noJumpCDStateConn then
            noJumpCDStateConn:Disconnect()
            noJumpCDStateConn = nil
        end

        noJumpCDStateConn = humanoid.StateChanged:Connect(function(oldState, newState)
            -- Cache JumpHeight when visible (game sets it to 0 during grounded states).
            local jh = humanoid.JumpHeight
            if jh > 0 then _cachedJumpHeight = jh end

            if debugLog and _jumpDiagCount < 30 then
                _jumpDiagCount = _jumpDiagCount + 1
                dlog("[JumpCD] " .. tostring(oldState) .. " -> " .. tostring(newState)
                    .. " | JumpHeight=" .. tostring(humanoid.JumpHeight)
                    .. " | Gravity=" .. tostring(workspace.Gravity))
            end

            -- No Jump CD: skip Landed state entirely so cooldown never applies.
            if isFeatureActive(noJumpCDSettings.Enabled, "NoJumpCDKey") then
                if newState == Enum.HumanoidStateType.Landed then
                    humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                end
            end
        end)
    end

    -- Hook current character.
    if localPlayer.Character then
        local hum = localPlayer.Character:FindFirstChild("Humanoid")
        if hum then setupJumpCD(hum) end
    end

    -- Re-hook on respawn.
    noJumpCDCharConn = localPlayer.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 10)
        if hum then setupJumpCD(hum) end
    end)

    -- Force jump with velocity + proper animation.
    local function forceJump(humanoid)
        if not humanoid then return end
        local character = humanoid.Parent
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not rootPart then return end

        local state = humanoid:GetState()
        if state ~= Enum.HumanoidStateType.Running
            and state ~= Enum.HumanoidStateType.RunningNoPhysics
            and state ~= Enum.HumanoidStateType.Landed then
            return
        end

        -- Must be on ground (Y velocity near zero).
        if math.abs(rootPart.AssemblyLinearVelocity.Y) > 3 then return end

        local now = tick()
        if now - _lastForceJump < 0.15 then return end
        _lastForceJump = now

        -- Calculate correct jump velocity from cached JumpHeight.
        local jumpVel
        if humanoid.UseJumpPower then
            jumpVel = humanoid.JumpPower
        else
            local gravity = workspace.Gravity
            if _cachedJumpHeight > 0 and gravity > 0 then
                jumpVel = math.sqrt(2 * gravity * _cachedJumpHeight)
            else
                jumpVel = 18
            end
        end
        if jumpVel <= 0 then jumpVel = 18 end

        -- Temporarily zero JumpHeight so engine applies no extra force during ChangeState.
        local origJH = humanoid.JumpHeight
        local origJP = humanoid.JumpPower
        humanoid.JumpHeight = 0
        humanoid.JumpPower = 0

        -- Apply our velocity + trigger Jumping state for animation.
        rootPart.AssemblyLinearVelocity = Vector3.new(
            rootPart.AssemblyLinearVelocity.X,
            jumpVel,
            rootPart.AssemblyLinearVelocity.Z
        )
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

        -- Restore after a frame so normal game systems aren't broken.
        task.defer(function()
            humanoid.JumpHeight = origJH
            humanoid.JumpPower = origJP
        end)
    end

    -- Heartbeat: bhop auto-jump when space held.
    noJumpCDConnection = runService.Heartbeat:Connect(function()
        if not isFeatureActive(noJumpCDSettings.Enabled, "NoJumpCDKey") then return end
        if not noJumpCDSettings.Bhop then return end

        local character = localPlayer.Character
        if not character then return end
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end

        if userInputService:IsKeyDown(Enum.KeyCode.Space) then
            forceJump(humanoid)
        end
    end)

    -- No Jump CD (without bhop): single space press triggers force jump.
    userInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode ~= Enum.KeyCode.Space then return end
        if not isFeatureActive(noJumpCDSettings.Enabled, "NoJumpCDKey") then return end
        local character = localPlayer.Character
        if not character then return end
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end
        forceJump(humanoid)
    end)

    local JumpGroup = Tabs.Movement:AddLeftGroupbox("Jump")

    JumpGroup:AddToggle("NoJumpCD", {
        Text = "No Jump Cooldown",
        Default = false,
        Callback = function(value) noJumpCDSettings.Enabled = value end,
    }):AddKeyPicker("NoJumpCDKey", {
        Default = "None",
        Text = "No Jump CD",
        NoUI = false,
    })

    JumpGroup:AddToggle("Bhop", {
        Text = "Bunny Hop",
        Default = false,
        Callback = function(value)
            noJumpCDSettings.Bhop = value
        end,
    })

    JumpGroup:AddLabel("Bhop = hold space to auto-jump")

    -- Forward declaration for spinSettings (used in third person loop).
    local spinSettings = {
        Enabled = false,
        Speed = 20,
    }

    -- ============================================================
    -- THIRD PERSON (fixed distance, always shift lock)
    -- ============================================================

    local tpCamSettings = {
        Enabled = false,
        Distance = 10,
        ShiftLock = true,
    }

    local originalCamMinZoom = nil
    local originalCamMaxZoom = nil
    local originalCamMode = nil
    local originalMouseBehavior = nil

    local function setThirdPerson(enabled)
        local playerObj = localPlayer

        if enabled then
            originalCamMinZoom = playerObj.CameraMinZoomDistance
            originalCamMaxZoom = playerObj.CameraMaxZoomDistance
            originalCamMode = playerObj.CameraMode
            originalMouseBehavior = userInputService.MouseBehavior

            -- Lock zoom to exact distance (no scroll zoom).
            playerObj.CameraMinZoomDistance = tpCamSettings.Distance
            playerObj.CameraMaxZoomDistance = tpCamSettings.Distance
            playerObj.CameraMode = Enum.CameraMode.Classic

            if tpCamSettings.ShiftLock then
                userInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            end
        else
            if originalCamMinZoom then
                playerObj.CameraMinZoomDistance = originalCamMinZoom
                playerObj.CameraMaxZoomDistance = originalCamMaxZoom or 0.5
            end
            playerObj.CameraMode = originalCamMode or Enum.CameraMode.LockFirstPerson
            userInputService.MouseBehavior = originalMouseBehavior or Enum.MouseBehavior.Default
        end
    end

    -- Enforce fixed distance + shift lock rotation every frame.
    runService.RenderStepped:Connect(function()
        if not isFeatureActive(tpCamSettings.Enabled, "ThirdPersonKey") then return end

        local character = localPlayer.Character
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")
        if not rootPart or not humanoid then return end

        -- Enforce fixed distance (prevent scroll zoom).
        localPlayer.CameraMinZoomDistance = tpCamSettings.Distance
        localPlayer.CameraMaxZoomDistance = tpCamSettings.Distance

        -- Always lock mouse to center so camera rotates without holding right click.
        local spinActive = isFeatureActive(spinSettings.Enabled, "SpinKey")
        if not spinActive and userInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            userInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end

        -- Shift lock: rotate character to face camera direction.
        -- Skip if shift lock is OFF or spinbot is active.
        if tpCamSettings.ShiftLock and not spinActive and humanoid.MoveDirection.Magnitude > 0 then
            local camLook = camera.CFrame.LookVector
            local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
            if flatLook.Magnitude > 0 then
                local pos = rootPart.Position
                rootPart.CFrame = CFrame.lookAt(pos, pos + flatLook)
            end
        end
    end)

    local TPCamGroup = Tabs.Movement:AddRightGroupbox("Third Person")

    TPCamGroup:AddToggle("ThirdPerson", {
        Text = "Enable Third Person",
        Default = false,
        Callback = function(value)
            tpCamSettings.Enabled = value
            setThirdPerson(value)
        end,
    }):AddKeyPicker("ThirdPersonKey", {
        Default = "None",
        Text = "Third Person",
        NoUI = false,
    })

    TPCamGroup:AddSlider("TPCamDist", {
        Text = "Camera Distance",
        Default = 10,
        Min = 2,
        Max = 30,
        Rounding = 0,
        Suffix = " studs",
        Callback = function(value)
            tpCamSettings.Distance = value
            if tpCamSettings.Enabled then
                localPlayer.CameraMinZoomDistance = value
                localPlayer.CameraMaxZoomDistance = value
            end
        end,
    })

    TPCamGroup:AddToggle("TPShiftLock", {
        Text = "Shift Lock",
        Default = true,
        Callback = function(value)
            tpCamSettings.ShiftLock = value
        end,
    })

    TPCamGroup:AddLabel("Fixed distance, no zoom")
    TPCamGroup:AddLabel("Shift lock = character faces cam")

    -- ============================================================
    -- SPINBOT
    -- ============================================================

    local spinAngle = 0
    local spinConnection = nil

    spinConnection = runService.RenderStepped:Connect(function(dt)
        if not isFeatureActive(spinSettings.Enabled, "SpinKey") then return end

        local character = localPlayer.Character
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not rootPart then return end

        -- Spin on Y axis.
        spinAngle = spinAngle + (math.pi * 2 * spinSettings.Speed * dt)
        if spinAngle > math.pi * 2 then spinAngle = spinAngle - math.pi * 2 end

        local pos = rootPart.CFrame.Position
        rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, spinAngle, 0)
    end)

    local SpinGroup = Tabs.Movement:AddRightGroupbox("Spinbot")

    SpinGroup:AddToggle("SpinEnabled", {
        Text = "Enable Spinbot",
        Default = false,
        Callback = function(value) spinSettings.Enabled = value; spinAngle = 0 end,
    }):AddKeyPicker("SpinKey", {
        Default = "None",
        Text = "Spinbot",
        NoUI = false,
    })

    SpinGroup:AddSlider("SpinSpeed", {
        Text = "Speed (rot/s)",
        Default = 20,
        Min = 1,
        Max = 50,
        Rounding = 0,
        Callback = function(value)
            spinSettings.Speed = value
        end,
    })

    SpinGroup:AddLabel("Spins your character model")
    SpinGroup:AddLabel("Visual only if FP camera")

    -- ============================================================
    -- ZOOM
    -- ============================================================

    local zoomSettings = {
        Enabled = false,
        Percent = 50, -- Zoom percentage (lower = more zoom)
    }

    local originalFieldOfView = nil
    local _zoomWasActive = false

    local function getZoomedFOV()
        local base = originalFieldOfView or camera.FieldOfView
        return math.clamp(base * (zoomSettings.Percent / 100), 1, 120)
    end

    local ZoomGroup = Tabs.Movement:AddRightGroupbox("Zoom")

    ZoomGroup:AddToggle("ZoomEnabled", {
        Text = "Enable Zoom",
        Default = false,
        Callback = function(value)
            zoomSettings.Enabled = value
            if value then
                if not _zoomWasActive then
                    originalFieldOfView = camera.FieldOfView
                    _zoomWasActive = true
                end
                camera.FieldOfView = getZoomedFOV()
            else
                if originalFieldOfView then
                    camera.FieldOfView = originalFieldOfView
                end
                originalFieldOfView = nil
                _zoomWasActive = false
            end
        end,
    }):AddKeyPicker("ZoomKey", {
        Default = "None",
        Text = "Zoom",
        NoUI = false,
    })

    ZoomGroup:AddSlider("ZoomLevel", {
        Text = "Zoom Amount",
        Default = 50,
        Min = 10,
        Max = 90,
        Rounding = 0,
        Suffix = "%",
        Callback = function(value)
            zoomSettings.Percent = value
            if zoomSettings.Enabled and _zoomWasActive then
                camera.FieldOfView = getZoomedFOV()
            end
        end,
    })

    ZoomGroup:AddLabel("Lower = more zoom")

    -- Keep zoom enforced while active, restore when inactive.
    runService.RenderStepped:Connect(function()
        local active = isFeatureActive(zoomSettings.Enabled, "ZoomKey")
        if active then
            if not _zoomWasActive then
                originalFieldOfView = camera.FieldOfView
                _zoomWasActive = true
            end
            local target = getZoomedFOV()
            if math.abs(camera.FieldOfView - target) > 0.1 then
                camera.FieldOfView = target
            end
        elseif _zoomWasActive then
            if originalFieldOfView then
                camera.FieldOfView = originalFieldOfView
            end
            originalFieldOfView = nil
            _zoomWasActive = false
        end
    end)

    -- ============================================================
    -- AIMBOT (Camera Lock)
    -- ============================================================

    local aimbotSettings = {
        Enabled = false,
        TargetPart = "Head",
        FOV = 250,
        ShowFOV = false,
        Smoothing = 5, -- 1 = instant snap, higher = smoother
    }

    local silentAimSettings = {
        Enabled = false,
        FOV = 250,
        ShowFOV = false,
    }

    -- Cached silent aim target (updated in RenderStepped, read in hook — avoids re-entrant __namecall).
    local silentAimActive = false
    local silentAimTargetPos = nil
    local silentAimTargetPart = nil -- Cached Part reference for instant/magic bullet

    -- Forward declarations: combat feature states.
    -- These MUST be declared before BindToRenderStep and hook closures that reference them,
    -- otherwise the closures capture globals instead of these locals.
    local instantBulletEnabled = false
    local instantBulletActive = false
    local magicBulletEnabled = false
    local magicBulletActive = false
    local stackShotsEnabled = false
    local stackShotsActive = false
    local storedShots = {}
    local releasingShots = false

    -- Silent aim FOV circle (separate from aimbot).
    local silentFovCircle = Drawing.new("Circle")
    silentFovCircle.Visible = false
    silentFovCircle.Color = Color3.fromRGB(255, 50, 50)
    silentFovCircle.Thickness = 1
    silentFovCircle.Filled = false
    silentFovCircle.Transparency = 0.6
    silentFovCircle.NumSides = 64

    -- FOV circle.
    local fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
    fovCircle.Thickness = 1
    fovCircle.Filled = false
    fovCircle.Transparency = 0.6
    fovCircle.NumSides = 64

    -- NPC targeting support.
    local aimbotNPCEnabled = false
    local silentAimNPCEnabled = false
    local aiZonesFolder = workspace:FindFirstChild("AiZones")

    local function validateTarget(char)
        if not char or not char:IsA("Model") then return false end
        if char.Name == localPlayer.Name then return false end

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local head = char:FindFirstChild("Head")
        if not humanoid or humanoid.Health <= 0 or not head then return false end

        -- Skip teammates (players only).
        if head:FindFirstChild("TeamMate") then return false end
        local myTeam = localPlayer:GetAttribute("TeamNum")
        local targetTeam = char:GetAttribute("TeamNum")
        if targetTeam and myTeam and targetTeam == myTeam then return false end

        return true
    end

    local function validateNPC(char)
        if not char or not char:IsA("Model") then return false end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local head = char:FindFirstChild("Head")
        if not humanoid or humanoid.Health <= 0 or not head then return false end
        return true
    end

    local function getNPCsFromAiZones()
        local npcs = {}
        for npc in pairs(cachedNPCSet) do
            if npc.Parent then
                table.insert(npcs, npc)
            end
        end
        return npcs
    end

    local function getClosestPlayerToCenter(fovOverride, includeNPCs)
        local closest = nil
        local closestDist = fovOverride or aimbotSettings.FOV
        local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

        -- Players.
        for _, player in ipairs(players:GetPlayers()) do
            if player == localPlayer then continue end
            local char = player.Character
            if not char or not validateTarget(char) then continue end

            local targetPart = char:FindFirstChild(aimbotSettings.TargetPart)
                or char:FindFirstChild("Head")
                or char:FindFirstChild("HumanoidRootPart")
            if not targetPart then continue end

            local screenPos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
            if not onScreen then continue end

            local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = targetPart
            end
        end

        -- NPCs from workspace.AiZones.
        if includeNPCs then
            for _, npc in ipairs(getNPCsFromAiZones()) do
                if not validateNPC(npc) then continue end

                local targetPart = npc:FindFirstChild(aimbotSettings.TargetPart)
                    or npc:FindFirstChild("Head")
                    or npc:FindFirstChild("HumanoidRootPart")
                if not targetPart then continue end

                local screenPos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
                if not onScreen then continue end

                local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = targetPart
                end
            end
        end

        return closest
    end

    -- Aimbot: move camera toward target while mouse is held.
    -- Use BindToRenderStep AFTER camera update so our CFrame isn't overwritten.
    runService:BindToRenderStep("AimbotAndCache", Enum.RenderPriority.Camera.Value + 1, function(dt)
        -- Update FOV circles.
        local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

        local aimbotActive = isFeatureActive(aimbotSettings.Enabled, "AimbotKey")
        fovCircle.Visible = aimbotActive and aimbotSettings.ShowFOV
        fovCircle.Radius = aimbotSettings.FOV
        fovCircle.Position = screenCenter

        local silentActive = isFeatureActive(silentAimSettings.Enabled, "SilentAimKey")
        local ibVisActive = isFeatureActive(instantBulletEnabled, "InstantBulletKey")
        local mbVisActive = isFeatureActive(magicBulletEnabled, "MagicBulletKey")
        silentFovCircle.Visible = (silentActive or ibVisActive or mbVisActive) and silentAimSettings.ShowFOV
        silentFovCircle.Radius = silentAimSettings.FOV
        silentFovCircle.Position = screenCenter

        -- Cache states for the hook (must be in same loop as target caching).
        silentAimActive = silentActive
        instantBulletActive = ibVisActive
        magicBulletActive = mbVisActive
        stackShotsActive = isFeatureActive(stackShotsEnabled, "StackShotsKey")

        -- Cache silent aim target for the hook (avoid re-entrant __namecall).
        local needsTarget = silentActive or ibVisActive or mbVisActive
        if needsTarget then
            local sTarget = getClosestPlayerToCenter(silentAimSettings.FOV, silentAimNPCEnabled)
            silentAimTargetPos = sTarget and sTarget.Position or nil
            silentAimTargetPart = sTarget
        else
            silentAimTargetPos = nil
            silentAimTargetPart = nil
        end

        -- Snaplines: draw line from crosshair to silent aim target.
        if snaplineSettings.Enabled and silentAimTargetPart then
            local sp, onS = camera:WorldToViewportPoint(silentAimTargetPart.Position)
            if onS then
                snapline.From = screenCenter
                snapline.To = Vector2.new(sp.X, sp.Y)
                snapline.Color = snaplineSettings.Color
                snapline.Visible = true
            else
                snapline.Visible = false
            end
        else
            snapline.Visible = false
        end

        -- Aimbot: smooth/snap camera to target when active (keybind handles hold/toggle/always).
        if aimbotActive then
            local target = getClosestPlayerToCenter(nil, aimbotNPCEnabled)
            if target then
                pcall(function()
                    local camPos = camera.CFrame.Position
                    local targetPos = target.Position
                    local targetCF = CFrame.lookAt(camPos, targetPos)

                    if aimbotSettings.Smoothing <= 1 then
                        camera.CFrame = targetCF
                    else
                        camera.CFrame = camera.CFrame:Lerp(targetCF, 1 / aimbotSettings.Smoothing)
                    end
                end)
            end
        end
    end)

    local fireProjectileRemote = remotesFolder and (remotesFolder:FindFirstChild("FireProjectile") or remotesFolder:WaitForChild("FireProjectile", 5))
    local projectileInflictRemote = remotesFolder and (remotesFolder:FindFirstChild("ProjectileInflict") or remotesFolder:WaitForChild("ProjectileInflict", 5))

    dlog("FireProjectile: " .. (fireProjectileRemote and fireProjectileRemote.ClassName or "NOT FOUND"))
    dlog("ProjectileInflict: " .. (projectileInflictRemote and projectileInflictRemote.ClassName or "NOT FOUND"))

    -- Aimbot UI.
    local AimbotGroup = Tabs.Combat:AddLeftGroupbox("Aimbot")

    AimbotGroup:AddToggle("Aimbot", {
        Text = "Enable Aimbot",
        Default = false,
        Callback = function(value) aimbotSettings.Enabled = value end,
    }):AddKeyPicker("AimbotKey", {
        Default = "None",
        Text = "Aimbot",
        NoUI = false,
    })

    AimbotGroup:AddToggle("ShowFOV", {
        Text = "Show FOV Circle",
        Default = false,
        Callback = function(value)
            aimbotSettings.ShowFOV = value
        end,
    })

    AimbotGroup:AddSlider("AimFOV", {
        Text = "FOV Radius",
        Default = 250,
        Min = 50,
        Max = 800,
        Rounding = 0,
        Suffix = " px",
        Callback = function(value)
            aimbotSettings.FOV = value
        end,
    })

    AimbotGroup:AddSlider("AimSmooth", {
        Text = "Smoothing",
        Default = 5,
        Min = 1,
        Max = 20,
        Rounding = 0,
        Callback = function(value)
            aimbotSettings.Smoothing = value
        end,
    })

    AimbotGroup:AddDropdown("AimTargetPart", {
        Text = "Target Part",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Default = 1,
        Callback = function(value)
            aimbotSettings.TargetPart = value
        end,
    })

    AimbotGroup:AddToggle("AimbotNPC", {
        Text = "Target NPCs",
        Default = false,
        Callback = function(value)
            aimbotNPCEnabled = value
        end,
    })

    AimbotGroup:AddLabel("Hold mouse to lock on")
    AimbotGroup:AddLabel("Smoothing 1 = instant snap")

    -- Silent Aim UI.
    local SilentGroup = Tabs.Combat:AddRightGroupbox("Silent Aim")

    SilentGroup:AddToggle("SilentAim", {
        Text = "Enable Silent Aim",
        Default = false,
        Callback = function(value) silentAimSettings.Enabled = value end,
    }):AddKeyPicker("SilentAimKey", {
        Default = "None",
        Text = "Silent Aim",
        NoUI = false,
    })

    SilentGroup:AddToggle("SilentNPC", {
        Text = "Target NPCs",
        Default = false,
        Callback = function(value)
            silentAimNPCEnabled = value
        end,
    })

    SilentGroup:AddToggle("SilentShowFOV", {
        Text = "Show FOV",
        Default = false,
        Callback = function(value)
            silentAimSettings.ShowFOV = value
        end,
    })

    SilentGroup:AddSlider("SilentFOV", {
        Text = "FOV Radius",
        Default = 250,
        Min = 30,
        Max = 800,
        Rounding = 0,
        Callback = function(value)
            silentAimSettings.FOV = value
        end,
    })

    SilentGroup:AddDivider()

    SilentGroup:AddToggle("InstantBullet", {
        Text = "Instant Bullet",
        Default = false,
        Callback = function(value) instantBulletEnabled = value end,
    }):AddKeyPicker("InstantBulletKey", {
        Default = "None",
        Text = "Instant Bullet",
        NoUI = false,
    })

    SilentGroup:AddLabel("Teleports bullet to target")
    SilentGroup:AddLabel("Hits through any wall")

    SilentGroup:AddDivider()

    SilentGroup:AddToggle("MagicBullet", {
        Text = "Magic Bullet",
        Default = false,
        Callback = function(value) magicBulletEnabled = value end,
    }):AddKeyPicker("MagicBulletKey", {
        Default = "None",
        Text = "Magic Bullet",
        NoUI = false,
    })

    SilentGroup:AddLabel("Shots go through walls")
    SilentGroup:AddLabel("Bullet still travels normally")

    SilentGroup:AddDivider()

    SilentGroup:AddToggle("StackShots", {
        Text = "Stack Shots",
        Default = false,
        Callback = function(value)
            stackShotsEnabled = value
            if not value and #storedShots > 0 then
                task.spawn(function()
                    local count = #storedShots
                    local shots = storedShots
                    storedShots = {}
                    releasingShots = true
                    for _, stored in ipairs(shots) do
                        pcall(function()
                            projectileInflictRemote:FireServer(unpack(stored, 1, stored.n))
                        end)
                    end
                    releasingShots = false
                    dlog("StackShots: released " .. count .. " shots")
                end)
            end
        end,
    }):AddKeyPicker("StackShotsKey", {
        Default = "None",
        Text = "Stack Shots",
        NoUI = false,
    })

    SilentGroup:AddLabel("Stores hits, releases on toggle off")

    -- ============================================================
    -- SILENT AIM + INSTANT BULLET + MAGIC BULLET + STACK SHOTS
    -- ============================================================
    -- Game architecture:
    --   Bullet raycast: workspace:Raycast(origin, dir * stepDist, params)
    --     → params.CollisionGroup = "WeaponRay" (identifies bullet raycasts)
    --   FireProjectile: InvokeServer(direction, randomId, tick())
    --   ProjectileInflict: FireServer(hitPart, hitPosObjectSpace, randomId, tick())

    local oldNamecall
    local _diagCounts = {raycast=0, fp=0, pi=0}
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        -- ── COMBAT: intercept bullet raycasts ──
        if method == "Raycast" and self == workspace and not checkcaller() then
            if silentAimTargetPos and (silentAimActive or instantBulletActive or magicBulletActive) then
                local origin = args[1]
                local direction = args[2]
                local params = args[3]

                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and params then
                    local isBullet = false
                    pcall(function()
                        isBullet = (params.CollisionGroup == "WeaponRay")
                    end)

                    if isBullet then
                        -- INSTANT BULLET: Include-filter only the target model.
                        if instantBulletActive and silentAimTargetPart then
                            local targetModel = silentAimTargetPart.Parent
                            if targetModel then
                                local ibParams = RaycastParams.new()
                                ibParams.FilterType = Enum.RaycastFilterType.Include
                                ibParams.FilterDescendantsInstances = {targetModel}
                                ibParams.CollisionGroup = "WeaponRay"

                                local livePos = silentAimTargetPart.Position
                                local newDir = (livePos - origin).Unit * direction.Magnitude
                                if _diagCounts.raycast < 3 then
                                    _diagCounts.raycast = _diagCounts.raycast + 1
                                    dlog("InstantBullet: redirected toward " .. targetModel.Name)
                                end
                                setnamecallmethod("Raycast")
                                return oldNamecall(self, origin, newDir, ibParams)
                            end

                        -- MAGIC BULLET: redirect toward target + filter walls on hit.
                        elseif magicBulletActive and silentAimTargetPart then
                            local stepDist = direction.Magnitude
                            local rayOrigin = origin
                            local remaining = stepDist

                            for i = 1, 10 do
                                local rayDir = (silentAimTargetPart.Position - rayOrigin).Unit * remaining
                                setnamecallmethod("Raycast")
                                local result = oldNamecall(self, rayOrigin, rayDir, params)

                                if not result then
                                    return nil
                                end

                                local hitInst = result.Instance
                                local isPlayer = false
                                pcall(function()
                                    local model = hitInst.Parent
                                    while model do
                                        if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
                                            isPlayer = true
                                            break
                                        end
                                        if model == workspace then break end
                                        model = model.Parent
                                    end
                                end)

                                if isPlayer then
                                    return result
                                end

                                pcall(function()
                                    local f = params.FilterDescendantsInstances
                                    table.insert(f, hitInst)
                                    if hitInst.Parent and hitInst.Parent ~= workspace then
                                        table.insert(f, hitInst.Parent)
                                    end
                                    params.FilterDescendantsInstances = f
                                end)

                                local hitDist = (result.Position - rayOrigin).Magnitude
                                remaining = remaining - hitDist - 0.1
                                if remaining <= 0.5 then return nil end
                                rayOrigin = result.Position + (silentAimTargetPart.Position - rayOrigin).Unit * 0.1
                            end
                            return nil

                        -- SILENT AIM: redirect direction, walls block normally.
                        elseif silentAimActive then
                            local newDir = (silentAimTargetPos - origin).Unit * direction.Magnitude
                            if _diagCounts.raycast < 3 then
                                _diagCounts.raycast = _diagCounts.raycast + 1
                                dlog("SilentAim: redirected raycast toward target")
                            end
                            setnamecallmethod("Raycast")
                            return oldNamecall(self, origin, newDir, params)
                        end
                    end
                end
            end
        end

        -- ── FIRE PROJECTILE: redirect direction for server validation ──
        if method == "InvokeServer" and self == fireProjectileRemote and not checkcaller() then
            if silentAimTargetPos and (silentAimActive or instantBulletActive or magicBulletActive) then
                if typeof(args[1]) == "Vector3" then
                    local origin = camera.CFrame.Position
                    local livePos = silentAimTargetPart and silentAimTargetPart.Position or silentAimTargetPos
                    args[1] = (livePos - origin).Unit
                    if _diagCounts.fp < 3 then
                        _diagCounts.fp = _diagCounts.fp + 1
                        dlog("FireProjectile: redirected direction")
                    end
                end
            end

            pcall(function()
                task.defer(function() pcall(fireTracer, args[1]) end)
            end)

            return oldNamecall(self, unpack(args))
        end

        -- ── STACK SHOTS: store ProjectileInflict damage calls ──
        if stackShotsActive and not releasingShots and not checkcaller()
            and method == "FireServer" and self == projectileInflictRemote then
            if #storedShots < 50 then
                local n = select("#", ...)
                local stored = {n = n, ...}
                table.insert(storedShots, stored)
                if _diagCounts.pi < 5 then
                    _diagCounts.pi = _diagCounts.pi + 1
                    dlog("StackShots: stored shot #" .. #storedShots)
                end
            end
            return nil
        end

        -- ── TRACER: also catch FireProjectile via FireServer (fallback) ──
        if method == "FireServer" and self == fireProjectileRemote then
            pcall(function()
                task.defer(function() pcall(fireTracer, args[1]) end)
            end)
        end

        return oldNamecall(self, unpack(args))
    end))

    dlog("__namecall hook active: SilentAim + InstantBullet + MagicBullet + StackShots + Tracers")

    -- Keybind sync is handled automatically by JopLib's SyncToggleState
    -- (set on every KeyPicker attached to a Toggle via :AddKeyPicker).

    -- ============================================================
    -- WATERMARK
    -- ============================================================

    Library:SetWatermarkVisibility(false)

    local FrameTimer = tick()
    local FrameCounter = 0
    local FPS = 60

    local WatermarkConnection = runService.RenderStepped:Connect(function()
        FrameCounter += 1

        if (tick() - FrameTimer) >= 1 then
            FPS = FrameCounter
            FrameTimer = tick()
            FrameCounter = 0
        end

        Library:SetWatermark(("Game Utility | %s fps | %s ms"):format(
            math.floor(FPS),
            math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
        ))
    end)

    -- ============================================================
    -- KEYBIND FRAME (hidden by default, toggle in UI Settings)
    -- ============================================================

    Library.KeybindFrame.Visible = false

    -- ============================================================
    -- UNLOAD HANDLER
    -- ============================================================

    Library:OnUnload(function()
        scriptUnloaded = true
        WatermarkConnection:Disconnect()

        -- Clean up player ESP.
        for _, esp in pairs(espObjects) do
            for key, drawing in pairs(esp) do
                if key == "bones" then
                    for _, bone in ipairs(drawing) do pcall(function() bone:Remove() end) end
                else
                    pcall(function() drawing:Remove() end)
                end
            end
        end
        espObjects = {}

        -- Clean up container ESP.
        for _, esp in pairs(containerESPObjects) do
            pcall(function() esp.text:Remove() end)
        end
        containerESPObjects = {}

        -- Clean up exit ESP.
        for _, esp in pairs(exitESPObjects) do
            pcall(function() esp.text:Remove() end)
        end
        exitESPObjects = {}

        -- Clean up corpse ESP.
        for _, esp in pairs(corpseESPObjects) do
            pcall(function() esp.text:Remove() end)
        end
        corpseESPObjects = {}

        -- Clean up explosive ESP.
        for _, esp in pairs(explosiveESPObjects) do
            pcall(function() esp.text:Remove() end)
        end
        explosiveESPObjects = {}

        -- Clean up NPC ESP.
        for npc, esp in pairs(npcESPObjects) do
            for key, drawing in pairs(esp) do
                if key == "bones" then
                    for _, bone in ipairs(drawing) do pcall(function() bone:Remove() end) end
                else
                    pcall(function() drawing:Remove() end)
                end
            end
        end
        npcESPObjects = {}

        -- Clean up snapline.
        pcall(function() snapline:Remove() end)

        -- Clean up speed.
        if speedConnection then speedConnection:Disconnect() end

        -- Clean up no jump cooldown.
        if noJumpCDConnection then noJumpCDConnection:Disconnect() end
        if noJumpCDStateConn then noJumpCDStateConn:Disconnect() end
        if noJumpCDCharConn then noJumpCDCharConn:Disconnect() end

        -- Clean up spider.
        if spiderConnection then spiderConnection:Disconnect() end

        -- Clean up spinbot.
        if spinConnection then spinConnection:Disconnect() end

        -- Clean up render step bindings.
        pcall(function() runService:UnbindFromRenderStep("AimbotAndCache") end)

        -- Remove FOV circles.
        pcall(function() fovCircle:Remove() end)
        pcall(function() silentFovCircle:Remove() end)

        -- Clear active tracers.
        for _, t in ipairs(activeTracers) do
            pcall(function() t.part:Destroy() end)
        end
        activeTracers = {}

        -- Restore fullbright and fog.
        pcall(function() setFullbright(false) end)
        pcall(function() setNoFog(false) end)

        -- Restore grass.
        pcall(function()
            sethiddenproperty(workspace.Terrain, "Decoration", true)
            sethiddenproperty(workspace.Terrain, "GrassLength", origGrassLength)
        end)

        -- Restore camera.
        if tpCamSettings.Enabled then setThirdPerson(false) end

        -- Restore namecall hook.
        pcall(function()
            if oldNamecall then hookmetamethod(game, "__namecall", oldNamecall) end
        end)

        -- Restore zoom.
        if zoomSettings.Enabled and originalFieldOfView then camera.FieldOfView = originalFieldOfView end

        -- Disable all settings to prevent lingering state.
        speedSettings.Enabled = false
        spiderSettings.Enabled = false
        noJumpCDSettings.Enabled = false
        spinSettings.Enabled = false
        tpCamSettings.Enabled = false
        zoomSettings.Enabled = false
        aimbotSettings.Enabled = false
        silentAimSettings.Enabled = false
        instantBulletEnabled = false
        magicBulletEnabled = false
        stackShotsEnabled = false
        releasingShots = false
        espSettings.Enabled = false
        npcESPSettings.Enabled = false
        containerESPSettings.Enabled = false
        exitESPSettings.Enabled = false
        corpseESPSettings.Enabled = false
        explosiveESPSettings.Enabled = false
        tracerSettings.Enabled = false
        snaplineSettings.Enabled = false

        print("[Script] Unloaded.")
        Library.Unloaded = true
    end)

    -- ============================================================
    -- UI SETTINGS TAB
    -- ============================================================

    local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

    MenuGroup:AddButton({
        Text = "Unload",
        Func = function() Library:Unload() end,
    })

    MenuGroup:AddLabel(""):AddKeyPicker("MenuKeybind", {
        Default = "End",
        NoUI = true,
        Text = "Menu keybind",
    })

    Library.ToggleKeybind = Options.MenuKeybind

    -- ============================================================
    -- THEME + CONFIG (addons)
    -- ============================================================

    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

    SaveManager:BuildConfigSection(Tabs["UI Settings"])
    ThemeManager:ApplyToTab(Tabs["UI Settings"], MenuGroup)

    -- Project Delta Logs (below GUI Logs in the Debug section)
    MenuGroup:AddToggle("DebugLog", {
        Text = "Project Delta Logs",
        Default = false,
        Callback = function(value)
            debugLog = value
            _jumpDiagCount = 0
            if value then print("[Project Delta] Logging enabled") end
        end,
    })

    -- ============================================================
    -- BYPASS STATUS (below configs)
    -- ============================================================

    local BypassGroup = Tabs["UI Settings"]:AddRightGroupbox("Bypass")
    BypassGroup:AddLabel("Overwatch: " .. bypassStatus)
    BypassGroup:AddLabel("Honeypots: Protected")

    -- ============================================================
    -- LOAD SAVED CONFIGS
    -- ============================================================

    SaveManager:LoadAutoloadConfig()
    ThemeManager:LoadAutoloadTheme()

    print("[Script] Loaded successfully!")
