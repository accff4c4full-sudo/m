--[=[
    MinhDZ Hub | Blox Fruits Main
    Standalone, modular Farm Level based on the supplied KaitunBF source.

    Implemented independent features:
      * Farm Level
      * Auto Equip Melee
      * Auto Buso (Haki)
      * Auto Sea Travel (unlock requirements still apply)

    Notes:
      * Farm Level is OFF by default.
      * Each feature has its own running flag/token.
      * Disabling Farm Level cancels its active flight and does not stop other features.
      * No global namecall hooks, hidden-property edits, anti-cheat bypass hooks,
        automatic server hopping, or unrelated Kaitun task orchestration are copied.
]=]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

--// Environment / re-execution cleanup
local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.MinhDZBloxFruitsHub and type(ENV.MinhDZBloxFruitsHub.Unload) == "function" then
    pcall(ENV.MinhDZBloxFruitsHub.Unload)
end

--// Fluent UI
local FLUENT_URL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
local Fluent = loadstring(game:HttpGet(FLUENT_URL))()

local Window = Fluent:CreateWindow({
    Title = "MinhDZ Hub | Blox Fruits",
    SubTitle = "Modular Main",
    TabWidth = 150,
    Size = UDim2.fromOffset(610, 500),
    Acrylic = false,
    Theme = "Dark",
    -- The floating MinhDZ button and our input listener control visibility.
    -- Disabling Fluent's own keybind avoids two visibility systems fighting.
    MinimizeKey = Enum.KeyCode.Unknown
})

local Tabs = {
    Farming = Window:AddTab({ Title = "Farming", Icon = "swords" }),
    Utility = Window:AddTab({ Title = "Utility", Icon = "zap" }),
    Travel = Window:AddTab({ Title = "Travel", Icon = "map" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// Independent floating menu control (keeps working while Fluent is hidden).
local FloatingGui = Instance.new("ScreenGui")
FloatingGui.Name = "MinhDZHubFloatingToggle"
FloatingGui.ResetOnSpawn = false
FloatingGui.IgnoreGuiInset = true
FloatingGui.DisplayOrder = 100000
FloatingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local floatingParent
pcall(function()
    floatingParent = game:GetService("CoreGui")
end)
local parentedToCoreGui = false
if floatingParent then
    parentedToCoreGui = pcall(function()
        FloatingGui.Parent = floatingParent
    end)
end
if not parentedToCoreGui then
    FloatingGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "MenuToggle"
ToggleButton.AnchorPoint = Vector2.new(0, 0.5)
ToggleButton.Position = UDim2.new(0, 16, 0.5, 0)
ToggleButton.Size = UDim2.fromOffset(116, 42)
ToggleButton.BackgroundColor3 = Color3.fromRGB(23, 18, 34)
ToggleButton.BackgroundTransparency = 0.08
ToggleButton.BorderSizePixel = 0
ToggleButton.AutoButtonColor = true
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "MZ  ·  HIDE"
ToggleButton.TextColor3 = Color3.fromRGB(205, 174, 255)
ToggleButton.TextSize = 12
ToggleButton.ZIndex = 10
ToggleButton.Parent = FloatingGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 9)
ToggleCorner.Parent = ToggleButton

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(157, 111, 225)
ToggleStroke.Thickness = 1.2
ToggleStroke.Transparency = 0.18
ToggleStroke.Parent = ToggleButton

local menuVisible = true
local function setMenuVisible(visible)
    menuVisible = visible == true
    if Fluent.GUI then
        Fluent.GUI.Enabled = menuVisible
    end
    ToggleButton.Text = menuVisible and "MZ  ·  HIDE" or "MZ  ·  OPEN"
    ToggleButton.TextColor3 = menuVisible
        and Color3.fromRGB(205, 174, 255)
        or Color3.fromRGB(165, 245, 195)
end

local toggleInputConnection = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightControl then
        setMenuVisible(not menuVisible)
    end
end)

ToggleButton.Activated:Connect(function()
    setMenuVisible(not menuVisible)
end)

--// Game remotes / modules used by the source script
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local CommF = RemotesFolder:WaitForChild("CommF_")
local NetFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
local RegisterAttack = NetFolder:WaitForChild("RE/RegisterAttack")
local RegisterHit = NetFolder:WaitForChild("RE/RegisterHit")

local GlobalModule
pcall(function()
    GlobalModule = require(ReplicatedStorage:WaitForChild("Global"))
end)

local QuestModule
local GuideModule
local function getQuestModule()
    if not QuestModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("Quests"))
        if ok and type(result) == "table" then
            QuestModule = result
        end
    end
    return QuestModule
end

local function getGuideModule()
    if not GuideModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("GuideModule"))
        if ok and type(result) == "table" then
            GuideModule = result
        end
    end
    return GuideModule
end

--// State
local Hub = {
    Unloading = false,
    Features = {
        FarmLevel = { Enabled = false, Token = 0 },
        AutoEquipMelee = { Enabled = false, Token = 0 },
        AutoBuso = { Enabled = false, Token = 0 },
        AutoSeaTravel = { Enabled = false, Token = 0 }
    },
    Settings = {
        FlightSpeed = 275,
        AttackHeight = 15,
        AttackInterval = 0.18,
        PreferredTeam = "Pirates",
        AutoJoinTeam = true
    },
    Status = "Ready",
    LastFarmQuestStart = 0,
    LastSeaTravel = 0,
    LastSeaCheck = 0,
    LastBusoCheck = 0,
    LastEquipCheck = 0,
    MismatchCount = 0,
    MovementToken = 0,
    SavedCollision = {}
}

ENV.MinhDZBloxFruitsHub = Hub

local function notify(title, content, duration)
    pcall(function()
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = duration or 4
        })
    end)
end

local function setStatus(message)
    Hub.Status = tostring(message)
    print("[MinhDZ Hub] " .. Hub.Status)
end

local function isFeatureActive(name, token)
    local feature = Hub.Features[name]
    return feature ~= nil
        and feature.Enabled
        and feature.Token == token
        and not Hub.Unloading
        and not Fluent.Unloaded
end

--// Character helpers
local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    return level and tonumber(level.Value) or nil
end

local function getSeaIndex()
    local mapAttribute = workspace:GetAttribute("MAP")
    if mapAttribute == "Sea1" then
        return 1
    elseif mapAttribute == "Sea2" then
        return 2
    elseif mapAttribute == "Sea3" then
        return 3
    end

    -- Same PlaceId fallback table used by the supplied KaitunBF script.
    local placeMap = {
        [2753915549] = 1,
        [79091703265657] = 2,
        [4442272183] = 2,
        [100117331123089] = 3,
        [7449423635] = 3
    }
    return placeMap[game.PlaceId] or 1
end

local function stripLevelSuffix(name)
    local value = tostring(name or "")
    value = value:gsub("%s*%[Lv%.?%s*%d+%]%s*", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function normalizeMobName(name)
    local value = stripLevelSuffix(name)
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d+%s+", "")
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "Military Soldiers" then
        value = "Military Soldier"
    end
    return value
end

local function mobNamesMatch(left, right)
    if not left or not right then
        return false
    end
    local a = normalizeMobName(left):lower()
    local b = normalizeMobName(right):lower()
    if a == b then
        return true
    end
    if #a > 1 and a:sub(-1) == "s" and a:sub(-2) ~= "ss" then
        a = a:sub(1, -2)
    end
    if #b > 1 and b:sub(-1) == "s" and b:sub(-2) ~= "ss" then
        b = b:sub(1, -2)
    end
    return a == b
end

--// Quest selection: follows the level/quest selection pattern in KaitunBF.
local BLACKLISTED_QUESTS = {
    BartiloQuest = true,
    CitizenQuest = true,
    Trainees = true,
    MarineQuest = true,
    ImpelQuest = true
}

local function selectQuestForLevel(level, sea)
    local quests = getQuestModule()
    if not quests then
        return nil, "ReplicatedStorage.Quests is unavailable"
    end

    local effectiveLevel = level
    if sea == 1 and effectiveLevel >= 700 then
        effectiveLevel = 699
    elseif sea == 2 and effectiveLevel >= 1500 then
        effectiveLevel = 1499
    end

    local best = nil
    local bestRequirement = -1

    for questId, stages in pairs(quests) do
        if not BLACKLISTED_QUESTS[questId] and type(stages) == "table" then
            for stageId, stage in pairs(stages) do
                local requiredLevel = tonumber(stage.LevelReq)
                local tasks = type(stage.Task) == "table" and stage.Task or nil

                if requiredLevel and tasks and requiredLevel <= effectiveLevel and requiredLevel >= bestRequirement then
                    for mobName, amount in pairs(tasks) do
                        local numericAmount = tonumber(amount) or 0
                        local normalizedName = normalizeMobName(mobName)
                        if numericAmount > 1
                            and normalizedName ~= "Gladiator"
                            and normalizedName ~= "Factory Staff" then
                            bestRequirement = requiredLevel
                            best = {
                                QuestId = questId,
                                StageId = stageId,
                                MobName = normalizedName,
                                LevelReq = requiredLevel,
                                QuestName = stage.Name
                            }
                        end
                    end
                end
            end
        end
    end

    if not best then
        return nil, "No level quest found for the current sea/level"
    end
    return best
end

--// Resolve quest-giver CFrame from GuideModule.Data.NPCList (same source data as KaitunBF).
local function getObjectCFrame(object)
    if typeof(object) == "CFrame" then
        return object
    elseif typeof(object) == "Vector3" then
        return CFrame.new(object)
    end
    if typeof(object) ~= "Instance" then
        return nil
    end
    if object:IsA("BasePart") then
        return object.CFrame
    elseif object:IsA("Attachment") then
        return object.WorldCFrame
    elseif object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if ok then
            return pivot
        end
    end
    local ok, cframe = pcall(function()
        return object.CFrame
    end)
    return ok and typeof(cframe) == "CFrame" and cframe or nil
end

local function getQuestGiverCFrame(requiredLevel)
    local guide = getGuideModule()
    local npcList = guide and guide.Data and guide.Data.NPCList
    if type(npcList) ~= "table" then
        return nil
    end

    for npcObject, npcInfo in pairs(npcList) do
        if type(npcInfo) == "table" and type(npcInfo.Levels) == "table" then
            for _, levelValue in ipairs(npcInfo.Levels) do
                if tonumber(levelValue) == tonumber(requiredLevel) then
                    local npcCFrame = getObjectCFrame(npcObject)
                    if not npcCFrame then
                        npcCFrame = getObjectCFrame(npcInfo.CFrame or npcInfo.NPC or npcInfo.Position)
                    end
                    if npcCFrame then
                        return npcCFrame
                    end
                end
            end
        end
    end
    return nil
end

--// Current quest parser based on KaitunBF's TrackedQuestFrame/Main.Quest parsing.
local function parseQuestMob(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local value = text
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d+%s+", "")
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and normalizeMobName(value) or nil
end

local function readActiveQuest()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil
    end

    local tracked = playerGui:FindFirstChild("TrackedQuestFrame")
    if tracked and tracked.Enabled then
        local frame = tracked:FindFirstChild("Frame")
        if frame then
            local description = frame:FindFirstChild("description")
            local header = frame:FindFirstChild("header")
            local headerLabel = header and header:FindFirstChild("textLabel")
            local headerText = headerLabel and headerLabel.Text or ""
            local descriptionText = description and description.Text or ""
            local mob = parseQuestMob(headerText)
            if not mob then
                mob = parseQuestMob(descriptionText)
            end
            if mob then
                return mob
            end
        end
    end

    local main = playerGui:FindFirstChild("Main")
    local questFrame = main and main:FindFirstChild("Quest")
    if questFrame and questFrame.Visible then
        local container = questFrame:FindFirstChild("Container")
        local titleFolder = container and container:FindFirstChild("QuestTitle")
        local title = titleFolder and titleFolder:FindFirstChild("Title")
        local mob = title and parseQuestMob(title.Text)
        if mob then
            return mob
        end
    end

    return nil
end

--// Movement: cancellable flight-style CFrame movement; collision values are restored.
local function restoreCollision()
    for part, originalValue in pairs(Hub.SavedCollision) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalValue
            end)
        end
    end
    table.clear(Hub.SavedCollision)
end

local function disableCollisionForCharacter(character)
    if not character then
        return
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if Hub.SavedCollision[descendant] == nil then
                Hub.SavedCollision[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

local function stopMovement()
    Hub.MovementToken = Hub.MovementToken + 1
    restoreCollision()
    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

local function moveTo(targetCFrame, farmToken)
    if typeof(targetCFrame) ~= "CFrame" then
        return false
    end

    Hub.MovementToken = Hub.MovementToken + 1
    local movementToken = Hub.MovementToken
    local character = getCharacter()
    local humanoid = getHumanoid()
    local root = getRoot()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    disableCollisionForCharacter(character)
    local movementCharacter = character
    local targetPosition = targetCFrame.Position
    while true do
        if not isFeatureActive("FarmLevel", farmToken) or movementToken ~= Hub.MovementToken then
            if movementToken == Hub.MovementToken then
                restoreCollision()
            end
            return false
        end

        character = getCharacter()
        humanoid = getHumanoid()
        root = getRoot()
        if not character or not humanoid or humanoid.Health <= 0 or not root then
            restoreCollision()
            return false
        end
        if character ~= movementCharacter then
            restoreCollision()
            movementCharacter = character
            disableCollisionForCharacter(character)
        end

        local offset = targetPosition - root.Position
        local distance = offset.Magnitude
        if distance <= 4 then
            break
        end

        local deltaTime = RunService.Heartbeat:Wait()
        local stepDistance = math.min(
            distance,
            Hub.Settings.FlightSpeed * math.clamp(deltaTime, 1 / 240, 1 / 20),
            18
        )
        local nextPosition = root.Position + offset.Unit * stepDistance
        root.CFrame = CFrame.new(nextPosition) * targetCFrame.Rotation
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if isFeatureActive("FarmLevel", farmToken) and movementToken == Hub.MovementToken then
        root.CFrame = targetCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if movementToken == Hub.MovementToken then
        restoreCollision()
    end
    return isFeatureActive("FarmLevel", farmToken)
end

--// Enemy helpers
local function findNearestQuestMob(mobName)
    local enemies = workspace:FindFirstChild("Enemies")
    local playerRoot = getRoot()
    if not enemies or not playerRoot then
        return nil
    end

    local closest, closestDistance = nil, math.huge
    for _, model in ipairs(enemies:GetChildren()) do
        if mobNamesMatch(model.Name, mobName) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                local distance = (root.Position - playerRoot.Position).Magnitude
                if distance < closestDistance then
                    closest = model
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

local function findMobSpawnCFrame(mobName)
    local spawnFolder = ReplicatedStorage:FindFirstChild("FortBuilderReplicatedSpawnPositionsFolder")
    if not spawnFolder then
        return nil
    end

    for _, spawnObject in ipairs(spawnFolder:GetChildren()) do
        local candidates = { spawnObject.Name, tostring(spawnObject) }
        if spawnObject:IsA("StringValue") then
            table.insert(candidates, spawnObject.Value)
        end
        for _, candidate in ipairs(candidates) do
            if mobNamesMatch(candidate, mobName) then
                local spawnCFrame = getObjectCFrame(spawnObject)
                if spawnCFrame then
                    return spawnCFrame
                end
            end
        end
    end
    return nil
end

--// Weapon helpers
local function getEquippedTool()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Tool")
end

local function equipMelee()
    local character = getCharacter()
    local humanoid = getHumanoid()
    if not character or not humanoid or humanoid.Health <= 0 then
        return false
    end

    local equipped = getEquippedTool()
    if equipped and (equipped.ToolTip == "Melee" or equipped.Name == "Combat") then
        return true
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        return false
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and (tool.ToolTip == "Melee" or tool.Name == "Combat") then
            humanoid:EquipTool(tool)
            return true
        end
    end
    return false
end

local function hasBuso()
    local ok, result = pcall(function()
        return LocalPlayer:HasTag("Buso")
    end)
    return ok and result == true
end

--// Combat: follows the source's RegisterAttack/RegisterHit + Global.SendHitsToServer flow.
local LastAttackAt = 0
local function attackNearbyQuestMobs(primaryTarget, mobName)
    if os.clock() - LastAttackAt < Hub.Settings.AttackInterval then
        return
    end

    local playerRoot = getRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    if not playerRoot or not enemies then
        return
    end

    local hitTargets = {}
    local hitPart = nil

    for _, model in ipairs(enemies:GetChildren()) do
        if mobNamesMatch(model.Name, mobName) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0
                and (root.Position - playerRoot.Position).Magnitude <= 60 then
                local candidatePart = model:FindFirstChild("Head") or model.PrimaryPart or root
                hitPart = hitPart or candidatePart
                table.insert(hitTargets, { model, root })
            end
        end
    end

    if #hitTargets == 0 or not hitPart then
        return
    end

    LastAttackAt = os.clock()
    local ok, err = pcall(function()
        RegisterAttack:FireServer(0.16, 1)
        if GlobalModule and type(GlobalModule.SendHitsToServer) == "function" then
            GlobalModule.SendHitsToServer(hitPart, hitTargets)
        else
            RegisterHit:FireServer(hitPart, hitTargets)
        end
    end)

    if not ok then
        warn("[MinhDZ Hub] Attack remote error: " .. tostring(err))
    end
end

--// Farm Level feature step
local function farmLevelStep(token)
    if not isFeatureActive("FarmLevel", token) then
        return
    end

    local level = getPlayerLevel()
    if not level then
        setStatus("Waiting for player level data...")
        task.wait(1)
        return
    end

    local sea = getSeaIndex()
    local quest, questError = selectQuestForLevel(level, sea)
    if not quest then
        setStatus(questError)
        task.wait(2)
        return
    end

    local activeMob = readActiveQuest()
    if activeMob and not mobNamesMatch(activeMob, quest.MobName) then
        Hub.MismatchCount = Hub.MismatchCount + 1
        if Hub.MismatchCount >= 2 then
            setStatus("Current quest does not match level quest; abandoning it...")
            pcall(function()
                CommF:InvokeServer("AbandonQuest")
            end)
            Hub.MismatchCount = 0
            Hub.LastFarmQuestStart = os.clock()
            task.wait(0.8)
        end
        return
    end

    if not activeMob then
        Hub.MismatchCount = 0
        if os.clock() - Hub.LastFarmQuestStart < 3 then
            return
        end

        local questGiver = getQuestGiverCFrame(quest.LevelReq)
        if questGiver then
            local root = getRoot()
            if root and (root.Position - questGiver.Position).Magnitude > 14 then
                setStatus(string.format("Travelling to quest giver | %s | Lv. %d", tostring(quest.QuestId), quest.LevelReq))
                moveTo(questGiver * CFrame.new(0, 4, 4), token)
                return
            end
        end

        if not isFeatureActive("FarmLevel", token) then
            return
        end

        setStatus(string.format("Accepting quest | %s | %s", tostring(quest.QuestId), quest.MobName))
        Hub.LastFarmQuestStart = os.clock()
        local ok, result = pcall(function()
            return CommF:InvokeServer("StartQuest", quest.QuestId, quest.StageId)
        end)
        if not ok then
            setStatus("StartQuest failed: " .. tostring(result))
        end
        task.wait(0.8)
        return
    end

    Hub.MismatchCount = 0
    local target = findNearestQuestMob(quest.MobName)
    if not target then
        local spawnCFrame = findMobSpawnCFrame(quest.MobName)
        if spawnCFrame then
            local root = getRoot()
            if root and (root.Position - spawnCFrame.Position).Magnitude > 25 then
                setStatus("Searching mob spawn | " .. quest.MobName)
                moveTo(spawnCFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token)
                return
            end
        end
        setStatus("Waiting for mob spawn | " .. quest.MobName)
        task.wait(1)
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
    local playerRoot = getRoot()
    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 or not playerRoot then
        return
    end

    local attackPosition = targetRoot.Position + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    local attackCFrame = CFrame.lookAt(attackPosition, targetRoot.Position)
    local distance = (playerRoot.Position - attackPosition).Magnitude

    if distance > 12 then
        setStatus(string.format("Farm Level | %s | travelling to mob", quest.MobName))
        moveTo(attackCFrame, token)
        return
    end

    playerRoot.CFrame = attackCFrame
    playerRoot.AssemblyLinearVelocity = Vector3.zero
    playerRoot.AssemblyAngularVelocity = Vector3.zero

    if Hub.Features.AutoEquipMelee.Enabled then
        equipMelee()
    end

    if not getEquippedTool() then
        setStatus("No weapon equipped; enable Auto Equip Melee or equip a weapon")
        task.wait(1)
        return
    end

    setStatus(string.format("Farm Level | %s | Lv. %d", quest.MobName, level))
    attackNearbyQuestMobs(target, quest.MobName)
    task.wait(0.08)
end

--// Auto Equip Melee is a separate feature.
local function autoEquipMeleeStep()
    if os.clock() - Hub.LastEquipCheck < 0.75 then
        return
    end
    Hub.LastEquipCheck = os.clock()
    if not equipMelee() then
        setStatus("Auto Equip Melee: no Melee tool found in Backpack")
    end
end

--// Auto Buso is a separate feature.
local function autoBusoStep()
    if os.clock() - Hub.LastBusoCheck < 5 then
        return
    end
    Hub.LastBusoCheck = os.clock()
    if hasBuso() then
        return
    end

    local ok, result = pcall(function()
        return CommF:InvokeServer("Buso")
    end)
    if not ok then
        warn("[MinhDZ Hub] Auto Buso error: " .. tostring(result))
    end
end

--// Auto Sea Travel: keeps the unlock checks visible and conservative.
local function getServerMeleeMastery(styleName)
    local highest = 0
    pcall(function()
        local itemServiceModule = ReplicatedStorage:FindFirstChild("ItemReplicationService")
        local itemConfigModule = ReplicatedStorage:FindFirstChild("ItemConfig")
        if not itemServiceModule or not itemConfigModule then
            return
        end

        local itemService = require(itemServiceModule)
        local itemConfig = require(itemConfigModule)
        local userCache = itemService._UserCache and itemService._UserCache[LocalPlayer.UserId]
        local masteryItems = userCache and userCache:GetItems("Mastery")
        if type(masteryItems) ~= "table" then
            return
        end

        local wanted = tostring(styleName):lower():gsub("[^%w]", "")
        for _, entry in pairs(masteryItems) do
            if entry and entry.ItemId then
                local ok, item = pcall(function()
                    return itemConfig.match(entry.ItemId):unwrap()
                end)
                local debugLabel = ok and item and item.Index and item.Index.DebugLabel
                if debugLabel then
                    local label = tostring(debugLabel):lower():gsub("[^%w]", "")
                    local matches = label == wanted or (wanted == "dragonclaw" and label == "dragonbreath")
                    if matches then
                        highest = math.max(highest, tonumber(entry.Value) or 0)
                    end
                end
            end
        end
    end)
    return highest
end

local function findDragonClawMastery()
    local mastery = getServerMeleeMastery("Dragon Claw")
    local owned = mastery > 0
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }
    for _, container in ipairs(containers) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.Name:lower():find("dragon claw", 1, true) or tool.Name:lower():find("dragon breath", 1, true)) then
                    owned = true
                    local masteryValue = tool:FindFirstChild("Level", true)
                    mastery = math.max(mastery, masteryValue and tonumber(masteryValue.Value) or 0)
                end
            end
        end
    end
    return mastery, owned
end

local function autoSeaTravelStep(token)
    if not isFeatureActive("AutoSeaTravel", token) then
        return
    end
    local level = getPlayerLevel()
    if not level then
        return
    end

    local sea = getSeaIndex()
    if os.clock() - Hub.LastSeaCheck < 10 then
        return
    end
    Hub.LastSeaCheck = os.clock()
    if os.clock() - Hub.LastSeaTravel < 60 then
        return
    end

    if sea == 1 and level >= 700 then
        Hub.LastSeaTravel = os.clock()
        setStatus("Checking Second Sea access...")
        pcall(function()
            CommF:InvokeServer("DressrosaQuestProgress", "Detective")
        end)
        task.wait(1)
        if not isFeatureActive("AutoSeaTravel", token) then
            return
        end
        local ok, result = pcall(function()
            return CommF:InvokeServer("TravelDressrosa")
        end)
        if ok then
            notify("MinhDZ Hub", "Second Sea travel request sent. Server unlock requirements still apply.", 5)
            setStatus("Second Sea travel requested | " .. tostring(result))
        else
            setStatus("Second Sea travel failed: " .. tostring(result))
        end
        return
    end

    if sea == 2 and level >= 1500 then
        local mastery, hasDragonClaw = findDragonClawMastery()
        if not hasDragonClaw or mastery < 400 then
            setStatus("Third Sea: Dragon Claw mastery 400 is still required by the source logic")
            return
        end

        local phoeyuDoorExists = false
        pcall(function()
            local map = workspace:FindFirstChild("Map")
            local iceCastle = map and map:FindFirstChild("IceCastle")
            local hall = iceCastle and iceCastle:FindFirstChild("Hall")
            local libraryDoor = hall and hall:FindFirstChild("LibraryDoor")
            phoeyuDoorExists = libraryDoor and libraryDoor:FindFirstChild("PhoeyuDoor") ~= nil
        end)

        if not phoeyuDoorExists then
            if not isFeatureActive("AutoSeaTravel", token) then
                return
            end
            Hub.LastSeaTravel = os.clock()
            setStatus("Checking Third Sea access...")
            local ok, result = pcall(function()
                return CommF:InvokeServer("TravelZou")
            end)
            if ok then
                notify("MinhDZ Hub", "Third Sea travel request sent. Server unlock requirements still apply.", 5)
                setStatus("Third Sea travel requested | " .. tostring(result))
            else
                setStatus("Third Sea travel failed: " .. tostring(result))
            end
        end
    end
end

--// Independent feature runner
local function startFeature(name, worker)
    local feature = Hub.Features[name]
    if not feature or feature.Enabled then
        return
    end

    feature.Enabled = true
    feature.Token = feature.Token + 1
    local token = feature.Token

    task.spawn(function()
        while isFeatureActive(name, token) do
            local ok, err = pcall(worker, token)
            if not ok then
                warn("[MinhDZ Hub] " .. name .. " error: " .. tostring(err))
                setStatus(name .. " error: " .. tostring(err))
                task.wait(1)
            else
                task.wait(0.12)
            end
        end
    end)

    notify("MinhDZ Hub", name .. " enabled", 3)
end

local function stopFeature(name)
    local feature = Hub.Features[name]
    if not feature or not feature.Enabled then
        return
    end

    feature.Enabled = false
    feature.Token = feature.Token + 1
    if name == "FarmLevel" then
        stopMovement()
        Hub.MismatchCount = 0
        setStatus("Farm Level stopped; movement cancelled")
    end
    notify("MinhDZ Hub", name .. " disabled", 3)
end

local function setFeature(name, enabled, worker)
    if enabled then
        startFeature(name, worker)
    else
        stopFeature(name)
    end
end

--// UI: each toggle starts/stops only its own module.
Tabs.Farming:AddParagraph({
    Title = "Farm Level",
    Content = "Select a level-appropriate quest, travel to its quest giver, accept it, locate the matching enemy and attack. This toggle starts only Farm Level."
})

Tabs.Farming:AddToggle("FarmLevel", {
    Title = "Farm Level",
    Description = "Auto travel to quest giver, accept quest and farm the matching mob.",
    Default = false,
    Callback = function(value)
        setFeature("FarmLevel", value, farmLevelStep)
    end
})

Tabs.Farming:AddButton({
    Title = "Stop Farm Level",
    Description = "Cancels Farm Level movement and attack loop only.",
    Callback = function()
        local option = Fluent.Options.FarmLevel
        if option then
            option:SetValue(false)
        else
            stopFeature("FarmLevel")
        end
    end
})

Tabs.Utility:AddParagraph({
    Title = "Independent utilities",
    Content = "These utilities have their own toggles. They do not start Farm Level."
})

Tabs.Utility:AddToggle("AutoEquipMelee", {
    Title = "Auto Equip Melee",
    Description = "Equip a Melee tool from Backpack independently.",
    Default = false,
    Callback = function(value)
        setFeature("AutoEquipMelee", value, autoEquipMeleeStep)
    end
})

Tabs.Utility:AddToggle("AutoBuso", {
    Title = "Auto Buso (Haki)",
    Description = "Enable Buso when it is not active.",
    Default = false,
    Callback = function(value)
        setFeature("AutoBuso", value, autoBusoStep)
    end
})

Tabs.Travel:AddParagraph({
    Title = "Sea Travel",
    Content = "Uses the travel calls and unlock checks found in the supplied KaitunBF source. It cannot complete missing story/puzzle requirements by itself."
})

Tabs.Travel:AddToggle("AutoSeaTravel", {
    Title = "Auto Sea Travel",
    Description = "Request Second Sea at Lv. 700; request Third Sea when Dragon Claw mastery conditions are met.",
    Default = false,
    Callback = function(value)
        setFeature("AutoSeaTravel", value, autoSeaTravelStep)
    end
})

Tabs.Settings:AddParagraph({
    Title = "Menu Visibility",
    Content = "Use the floating MZ button to hide or reopen the menu. RightControl is also a visibility shortcut; hiding the menu does not stop enabled features."
})

Tabs.Settings:AddParagraph({
    Title = "Team Selection",
    Content = "Choose the team MinhDZ requests when the character has not spawned yet. The default is Pirates. Team selection is skipped if you are already in-game."
})

Tabs.Settings:AddDropdown("PreferredTeam", {
    Title = "Preferred Team",
    Description = "Used by Auto Join Team during the game's team-selection stage.",
    Values = { "Pirates", "Marines" },
    Default = Hub.Settings.PreferredTeam,
    Callback = function(value)
        if value == "Pirates" or value == "Marines" then
            Hub.Settings.PreferredTeam = value
        end
    end
})

Tabs.Settings:AddToggle("AutoJoinTeam", {
    Title = "Auto Join Team on Startup",
    Description = "Requests the selected team after the game finishes loading.",
    Default = true,
    Callback = function(value)
        Hub.Settings.AutoJoinTeam = value == true
    end
})

Tabs.Settings:AddSlider("FlightSpeed", {
    Title = "Flight Speed",
    Description = "CFrame movement speed used while travelling to quest givers and mobs.",
    Default = 275,
    Min = 80,
    Max = 325,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.FlightSpeed = math.clamp(tonumber(value) or 275, 80, 325)
    end
})

Tabs.Settings:AddSlider("AttackHeight", {
    Title = "Attack Height",
    Description = "Vertical offset above the target mob.",
    Default = 15,
    Min = 8,
    Max = 60,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.AttackHeight = math.clamp(tonumber(value) or 15, 8, 60)
    end
})

Tabs.Settings:AddSlider("AttackInterval", {
    Title = "Attack Interval",
    Description = "Delay between attack remote calls.",
    Default = 0.18,
    Min = 0.12,
    Max = 0.6,
    Rounding = 2,
    Callback = function(value)
        Hub.Settings.AttackInterval = math.clamp(tonumber(value) or 0.18, 0.12, 0.6)
    end
})

Tabs.Settings:AddButton({
    Title = "Stop All Features",
    Description = "Stops every enabled feature and cancels active movement.",
    Callback = function()
        local optionNames = {
            FarmLevel = "FarmLevel",
            AutoEquipMelee = "AutoEquipMelee",
            AutoBuso = "AutoBuso",
            AutoSeaTravel = "AutoSeaTravel"
        }
        for featureName, optionName in pairs(optionNames) do
            local option = Fluent.Options[optionName]
            if option and Hub.Features[featureName].Enabled then
                option:SetValue(false)
            else
                stopFeature(featureName)
            end
        end
        stopMovement()
        notify("MinhDZ Hub", "All features stopped", 4)
    end
})

Tabs.Settings:AddButton({
    Title = "Unload Hub",
    Description = "Stops all loops, restores collisions and removes the Fluent UI.",
    Callback = function()
        Hub.Unload()
    end
})

function Hub.Unload()
    if Hub.Unloading then
        return
    end
    Hub.Unloading = true
    for _, feature in pairs(Hub.Features) do
        feature.Enabled = false
        feature.Token = feature.Token + 1
    end
    stopMovement()
    if toggleInputConnection then
        pcall(function()
            toggleInputConnection:Disconnect()
        end)
        toggleInputConnection = nil
    end
    pcall(function()
        FloatingGui:Destroy()
    end)
    pcall(function()
        Fluent:Destroy()
    end)
end

Window:SelectTab(1)

--// Auto team selection: mirrors KaitunBF's SetTeam request but permits either faction.
-- This only runs while the player has not spawned. It never attempts to switch a live character.
task.spawn(function()
    if not Hub.Settings.AutoJoinTeam then
        return
    end

    local loadDeadline = os.clock() + 90
    while not Hub.Unloading do
        local loaded = false
        pcall(function()
            loaded = game:IsLoaded() and LocalPlayer:FindFirstChild("DataLoaded") ~= nil
        end)
        if loaded then
            break
        end
        if os.clock() >= loadDeadline then
            setStatus("Auto Join Team timed out while waiting for game data")
            notify("MinhDZ Hub", "Team selection timed out; you can still choose a team manually.", 6)
            return
        end
        task.wait(0.25)
    end

    if Hub.Unloading then
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local loadingDeadline = os.clock() + 30
    while playerGui and playerGui:FindFirstChild("LoadingScreen") and os.clock() < loadingDeadline and not Hub.Unloading do
        task.wait(0.25)
    end

    -- Give the Settings dropdown time to be changed before requesting the faction.
    task.wait(5)
    if Hub.Unloading or not Hub.Settings.AutoJoinTeam then
        return
    end

    if LocalPlayer.Character then
        setStatus("Character already spawned; Auto Join Team skipped")
        return
    end

    local requestedTeam = nil
    for attempt = 1, 8 do
        if Hub.Unloading or not Hub.Settings.AutoJoinTeam or LocalPlayer.Character then
            break
        end
        local selectedTeam = Hub.Settings.PreferredTeam
        if selectedTeam ~= "Pirates" and selectedTeam ~= "Marines" then
            selectedTeam = "Pirates"
        end
        requestedTeam = selectedTeam
        local ok, result = pcall(function()
            return CommF:InvokeServer("SetTeam", selectedTeam)
        end)
        if not ok then
            setStatus("SetTeam request failed: " .. tostring(result))
        else
            setStatus("Joining " .. selectedTeam .. "...")
        end
        task.wait(1)
    end

    if LocalPlayer.Character then
        notify("MinhDZ Hub", "Joined as " .. tostring(LocalPlayer.Team and LocalPlayer.Team.Name or requestedTeam or "selected team"), 5)
    elseif not Hub.Unloading and Hub.Settings.AutoJoinTeam then
        notify("MinhDZ Hub", "Team request sent. If the selection screen remains open, choose the team manually.", 7)
    end
end)

Fluent:Notify({
    Title = "MinhDZ Hub",
    Content = "Loaded. All features are OFF by default.",
    Duration = 6
})

print("[MinhDZ Hub] Loaded | Farm Level, Auto Equip Melee, Auto Buso, Auto Sea Travel")
