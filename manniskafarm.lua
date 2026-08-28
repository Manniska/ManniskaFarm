-- =====================================================================
--  MANNISKAFARM V14.0 - MASTER TABLE ARCHITECTURE & KINEMATIC SUITE
-- =====================================================================

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Color Presets
local THEMES = {
    ["Midnight Blue"] = {
        Background = Color3.fromRGB(14, 16, 22), Surface = Color3.fromRGB(22, 26, 36),
        Border = Color3.fromRGB(42, 50, 70), Accent = Color3.fromRGB(0, 162, 255),
        RecordActive = Color3.fromRGB(240, 70, 70), PlayActive = Color3.fromRGB(46, 204, 113),
        ToggleOff = Color3.fromRGB(32, 38, 52), TextPrimary = Color3.fromRGB(245, 246, 250),
        TextSecondary = Color3.fromRGB(140, 148, 170), GradientEnabled = true, GradientColor = Color3.fromRGB(0, 80, 160)
    },
    ["Dark Charcoal"] = {
        Background = Color3.fromRGB(16, 16, 16), Surface = Color3.fromRGB(24, 24, 24),
        Border = Color3.fromRGB(45, 45, 45), Accent = Color3.fromRGB(215, 215, 215),
        RecordActive = Color3.fromRGB(240, 70, 70), PlayActive = Color3.fromRGB(46, 204, 113),
        ToggleOff = Color3.fromRGB(36, 36, 36), TextPrimary = Color3.fromRGB(245, 245, 245),
        TextSecondary = Color3.fromRGB(150, 150, 150), GradientEnabled = false
    }
}

local currentThemeName = "Midnight Blue"
local activeTheme = THEMES[currentThemeName]
local CustomThemeData = { Hue = 0.58, Saturation = 0.8, Brightness = 0.9, GradientEnabled = true }

local Keybinds = {
    ToggleMenu = Enum.KeyCode.RightShift, ToggleRecord = Enum.KeyCode.R,
    TogglePlay = Enum.KeyCode.P, UndoNode = Enum.KeyCode.Z
}

local TWEEN_QUICK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local Config = {
    PlaybackMode = "Loop", SpeedMultiplier = 1.0, TargetLoops = 0,
    StatusHUDEnabled = true, VisualizerEnabled = true, RealtimeVisualizer = true, VisualizerOpacity = 0.2,
    WaypointLabelsEnabled = true, AutoUnstuckEnabled = false, AntiAFKEnabled = true, EmergencyLeaveOnDeath = true,
    FileName = "ManniskaFarm_Route.json", MicroRandomization = true, AutoTeleport = false, FallDamper = false,
    SpeedCurves = true, AutoRejoin = false, SegmentLooping = false, SegmentStart = 1, SegmentEnd = 5,
    SegmentRepeats = 2, ProximityRadar = false, RadarRadius = 60, RadarAction = "Pause",
    UseExternalBridge = true, BridgeFileName = "macro_bridge.txt", RecordMouseClicks = false
}

if writefile then pcall(function() writefile(Config.BridgeFileName, "IDLE:0") end) end

-- =====================================================================
--  MASTER TABLE ARCHITECTURE (FIXES EXECUTOR NIL BUGS)
-- =====================================================================
local Core = {
    Waypoints = {},
    isRecording = false,
    isPlaying = false,
    currentLoopCount = 0,
    jumpTriggered = false,
    lastWaypointTime = 0,
    holdStartTick = nil,
    mb1StartTick = nil,
    scriptConnections = {},
    activeToggles = {},
    visualizerPool = { Nodes = {}, Beams = {}, Labels = {} },
    renderTicket = 0,
    lastBridgeWriteTick = 0,
    bridgeQueue = nil,
    UI = {}
}

Core.playSoundFeedback = function(pitch)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxasset://sounds/button.wav"
        sound.Volume = 0.4; sound.PlaybackSpeed = pitch or 1.0
        sound.Parent = workspace; sound:Play()
        task.delay(1, function() if sound and sound.Parent then sound:Destroy() end end)
    end)
end

Core.getCharacter = function()
    local char = player.Character
    local camera = workspace.CurrentCamera
    if not char or not char.Parent then
        char = workspace:FindFirstChild(player.Name)
        if not char then
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Model") and (obj.Name == player.Name or obj:FindFirstChild(player.Name)) then char = obj break end
            end
        end
    end

    local hum = nil
    local root = nil
    if char and typeof(char) == "Instance" then
        hum = char:FindFirstChildWhichIsA("Humanoid", true)
        if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then root = char.PrimaryPart end
        if not root then
            local candidates = { "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "RootPart", "Hitbox", "Main", "Body", "Chest", "Center", "Root", "Head", "RightUpperLeg", "LeftUpperLeg" }
            for _, name in ipairs(candidates) do
                local found = char:FindFirstChild(name, true)
                if found and found:IsA("BasePart") then root = found break end
            end
        end
        if not root and hum and hum.SeatPart then
            local seat = hum.SeatPart
            if seat:IsA("BasePart") then root = seat
            elseif seat.Parent and seat.Parent:IsA("Model") and seat.Parent.PrimaryPart then root = seat.Parent.PrimaryPart end
        end
        if not root then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and not part.Anchored then root = part break end
            end
        end
    end

    if not root and camera and camera.CameraSubject then
        local subj = camera.CameraSubject
        if subj:IsA("BasePart") then root = subj char = subj.Parent
        elseif subj:IsA("Humanoid") and subj.Parent then char = subj.Parent hum = subj root = char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart", true) end
    end
    return char, root, hum
end

Core.getEntityPosition = function()
    local _, root, _ = Core.getCharacter()
    if root and root:IsA("BasePart") then return root.Position end
    return nil
end

-- =====================================================================
--  UI CONSTRUCTION (BOUND TO CORE)
-- =====================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ManniskaFarmUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local themeElements = { Background = {}, Surface = {}, Border = {}, AccentText = {}, AccentBg = {}, TextPrimary = {}, TextSecondary = {}, ToggleOff = {} }
local function registerElement(category, obj, prop)
    if not themeElements[category] then themeElements[category] = {} end
    table.insert(themeElements[category], { Object = obj, Property = prop })
end

Core.UI.errorModal = Instance.new("Frame")
Core.UI.errorModal.Name = "ErrorModal"
Core.UI.errorModal.Size = UDim2.new(0, 360, 0, 140)
Core.UI.errorModal.Position = UDim2.new(0.5, -180, 0.4, -70)
Core.UI.errorModal.BackgroundColor3 = Color3.fromRGB(24, 14, 18)
Core.UI.errorModal.BorderSizePixel = 0
Core.UI.errorModal.ZIndex = 50
Core.UI.errorModal.Visible = false
Core.UI.errorModal.Parent = screenGui
local errCorner = Instance.new("UICorner"); errCorner.CornerRadius = UDim.new(0, 10); errCorner.Parent = Core.UI.errorModal
local errStroke = Instance.new("UIStroke"); errStroke.Thickness = 1.5; errStroke.Color = Color3.fromRGB(240, 70, 70); errStroke.Transparency = 0.2; errStroke.Parent = Core.UI.errorModal

Core.UI.errCodeLabel = Instance.new("TextLabel")
Core.UI.errCodeLabel.Size = UDim2.new(1, -24, 0, 16); Core.UI.errCodeLabel.Position = UDim2.new(0, 14, 0, 34)
Core.UI.errCodeLabel.BackgroundTransparency = 1; Core.UI.errCodeLabel.TextColor3 = Color3.fromRGB(180, 140, 150)
Core.UI.errCodeLabel.TextSize = 10; Core.UI.errCodeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); Core.UI.errCodeLabel.TextXAlignment = Enum.TextXAlignment.Left
Core.UI.errCodeLabel.ZIndex = 51; Core.UI.errCodeLabel.Parent = Core.UI.errorModal

Core.UI.errDesc = Instance.new("TextLabel")
Core.UI.errDesc.Size = UDim2.new(1, -28, 0, 40); Core.UI.errDesc.Position = UDim2.new(0, 14, 0, 54)
Core.UI.errDesc.BackgroundTransparency = 1; Core.UI.errDesc.TextColor3 = Color3.fromRGB(240, 240, 245)
Core.UI.errDesc.TextSize = 11; Core.UI.errDesc.TextWrapped = true; Core.UI.errDesc.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); Core.UI.errDesc.TextXAlignment = Enum.TextXAlignment.Left
Core.UI.errDesc.ZIndex = 51; Core.UI.errDesc.Parent = Core.UI.errorModal

local errDismissBtn = Instance.new("TextButton")
errDismissBtn.Size = UDim2.new(1, -28, 0, 26); errDismissBtn.Position = UDim2.new(0, 14, 1, -34)
errDismissBtn.BackgroundColor3 = Color3.fromRGB(45, 20, 28); errDismissBtn.BorderSizePixel = 0
errDismissBtn.Text = "Dismiss"; errDismissBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
errDismissBtn.TextSize = 11; errDismissBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); errDismissBtn.ZIndex = 51; errDismissBtn.Parent = Core.UI.errorModal
local errBtnCorner = Instance.new("UICorner"); errBtnCorner.CornerRadius = UDim.new(0, 6); errBtnCorner.Parent = errDismissBtn
errDismissBtn.MouseButton1Click:Connect(function() Core.UI.errorModal.Visible = false end)

Core.triggerErrorModal = function(errorCode, description)
    Core.UI.errCodeLabel.Text = "CODE: " .. tostring(errorCode)
    Core.UI.errDesc.Text = tostring(description)
    Core.UI.errorModal.Visible = true
    Core.playSoundFeedback(0.7)
end

Core.UI.statusHUD = Instance.new("Frame")
Core.UI.statusHUD.Name = "PersistentStatusHUD"
Core.UI.statusHUD.Size = UDim2.new(0, 310, 0, 38); Core.UI.statusHUD.Position = UDim2.new(1, -322, 0, 12)
Core.UI.statusHUD.BackgroundColor3 = activeTheme.Background; Core.UI.statusHUD.BackgroundTransparency = 0.2; Core.UI.statusHUD.BorderSizePixel = 0
Core.UI.statusHUD.Visible = Config.StatusHUDEnabled; Core.UI.statusHUD.Parent = screenGui
registerElement("Background", Core.UI.statusHUD, "BackgroundColor3")
local hudCorner = Instance.new("UICorner"); hudCorner.CornerRadius = UDim.new(0, 8); hudCorner.Parent = Core.UI.statusHUD
local hudStroke = Instance.new("UIStroke"); hudStroke.Thickness = 1; hudStroke.Color = activeTheme.Border; hudStroke.Transparency = 0.3; hudStroke.Parent = Core.UI.statusHUD

Core.UI.hudBadge = Instance.new("Frame")
Core.UI.hudBadge.Size = UDim2.new(0, 48, 0, 20); Core.UI.hudBadge.Position = UDim2.new(0, 10, 0.5, -10)
Core.UI.hudBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 80); Core.UI.hudBadge.BorderSizePixel = 0; Core.UI.hudBadge.Parent = Core.UI.statusHUD
local hudBadgeCorner = Instance.new("UICorner"); hudBadgeCorner.CornerRadius = UDim.new(0, 4); hudBadgeCorner.Parent = Core.UI.hudBadge

Core.UI.hudBadgeLabel = Instance.new("TextLabel")
Core.UI.hudBadgeLabel.Size = UDim2.new(1, 0, 1, 0); Core.UI.hudBadgeLabel.BackgroundTransparency = 1
Core.UI.hudBadgeLabel.Text = "IDLE"; Core.UI.hudBadgeLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
Core.UI.hudBadgeLabel.TextSize = 9; Core.UI.hudBadgeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); Core.UI.hudBadgeLabel.Parent = Core.UI.hudBadge

Core.UI.hudNodeLabel = Instance.new("TextLabel")
Core.UI.hudNodeLabel.Size = UDim2.new(0, 110, 1, 0); Core.UI.hudNodeLabel.Position = UDim2.new(0, 66, 0, 0)
Core.UI.hudNodeLabel.BackgroundTransparency = 1; Core.UI.hudNodeLabel.Text = "Node: 0/0"
Core.UI.hudNodeLabel.TextColor3 = activeTheme.TextPrimary; Core.UI.hudNodeLabel.TextSize = 11; Core.UI.hudNodeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); Core.UI.hudNodeLabel.TextXAlignment = Enum.TextXAlignment.Left; Core.UI.hudNodeLabel.Parent = Core.UI.statusHUD
registerElement("TextPrimary", Core.UI.hudNodeLabel, "TextColor3")

Core.UI.hudLoopLabel = Instance.new("TextLabel")
Core.UI.hudLoopLabel.Size = UDim2.new(0, 120, 1, 0); Core.UI.hudLoopLabel.Position = UDim2.new(1, -130, 0, 0)
Core.UI.hudLoopLabel.BackgroundTransparency = 1; Core.UI.hudLoopLabel.Text = "Loop: 0/Inf | 1.0x"
Core.UI.hudLoopLabel.TextColor3 = activeTheme.Accent; Core.UI.hudLoopLabel.TextSize = 11; Core.UI.hudLoopLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); Core.UI.hudLoopLabel.TextXAlignment = Enum.TextXAlignment.Right; Core.UI.hudLoopLabel.Parent = Core.UI.statusHUD
registerElement("AccentText", Core.UI.hudLoopLabel, "TextColor3")

local hudDragging, hudDragStart, hudStartPos = false, nil, nil
Core.UI.statusHUD.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        hudDragging = true; hudDragStart = input.Position; hudStartPos = Core.UI.statusHUD.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then hudDragging = false end end)
    end
end)
local hudMoveConn = UserInputService.InputChanged:Connect(function(input)
    if hudDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - hudDragStart
        Core.UI.statusHUD.Position = UDim2.new(hudStartPos.X.Scale, hudStartPos.X.Offset + delta.X, hudStartPos.Y.Scale, hudStartPos.Y.Offset + delta.Y)
    end
end)
table.insert(Core.scriptConnections, hudMoveConn)

Core.UI.mainFrame = Instance.new("Frame")
Core.UI.mainFrame.Name = "MainWindow"
Core.UI.mainFrame.Size = UDim2.new(0, 440, 0, 520); Core.UI.mainFrame.Position = UDim2.new(0.5, -220, 0.32, -260)
Core.UI.mainFrame.BackgroundColor3 = activeTheme.Background; Core.UI.mainFrame.BackgroundTransparency = 0.15; Core.UI.mainFrame.BorderSizePixel = 0; Core.UI.mainFrame.ClipsDescendants = true; Core.UI.mainFrame.Parent = screenGui
registerElement("Background", Core.UI.mainFrame, "BackgroundColor3")
local mainCorner = Instance.new("UICorner"); mainCorner.CornerRadius = UDim.new(0, 12); mainCorner.Parent = Core.UI.mainFrame
local mainStroke = Instance.new("UIStroke"); mainStroke.Thickness = 1.2; mainStroke.Color = activeTheme.Border; mainStroke.Transparency = 0.2; mainStroke.Parent = Core.UI.mainFrame

Core.UI.bgGradient = Instance.new("UIGradient")
Core.UI.bgGradient.Rotation = 45
Core.UI.bgGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, activeTheme.Background), ColorSequenceKeypoint.new(1, activeTheme.GradientColor or activeTheme.Background) })
Core.UI.bgGradient.Enabled = (activeTheme.GradientEnabled == true); Core.UI.bgGradient.Parent = Core.UI.mainFrame

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 48); header.BackgroundColor3 = activeTheme.Surface; header.BackgroundTransparency = 0.2; header.BorderSizePixel = 0; header.Parent = Core.UI.mainFrame
registerElement("Surface", header, "BackgroundColor3")
local headerPadding = Instance.new("UIPadding"); headerPadding.PaddingLeft = UDim.new(0, 14); headerPadding.PaddingRight = UDim.new(0, 10); headerPadding.Parent = header

local titleGroup = Instance.new("Frame")
titleGroup.Size = UDim2.new(1, -110, 1, 0); titleGroup.BackgroundTransparency = 1; titleGroup.Parent = header
local titleLayout = Instance.new("UIListLayout"); titleLayout.FillDirection = Enum.FillDirection.Vertical; titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center; titleLayout.Padding = UDim.new(0, 2); titleLayout.Parent = titleGroup

local titleTopRow = Instance.new("Frame")
titleTopRow.Size = UDim2.new(1, 0, 0, 16); titleTopRow.BackgroundTransparency = 1; titleTopRow.Parent = titleGroup
local titleTopLayout = Instance.new("UIListLayout"); titleTopLayout.FillDirection = Enum.FillDirection.Horizontal; titleTopLayout.VerticalAlignment = Enum.VerticalAlignment.Center; titleTopLayout.Padding = UDim.new(0, 8); titleTopLayout.Parent = titleTopRow

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 145, 1, 0); titleLabel.BackgroundTransparency = 1; titleLabel.Text = "MANNISKAFARM V14.0"
titleLabel.TextColor3 = activeTheme.TextPrimary; titleLabel.TextSize = 13; titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.Parent = titleTopRow

Core.UI.stateBadge = Instance.new("Frame")
Core.UI.stateBadge.Size = UDim2.new(0, 56, 0, 16); Core.UI.stateBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 80); Core.UI.stateBadge.BackgroundTransparency = 0.2; Core.UI.stateBadge.BorderSizePixel = 0; Core.UI.stateBadge.Parent = titleTopRow
local stateBadgeCorner = Instance.new("UICorner"); stateBadgeCorner.CornerRadius = UDim.new(0, 4); stateBadgeCorner.Parent = Core.UI.stateBadge

Core.UI.stateBadgeLabel = Instance.new("TextLabel")
Core.UI.stateBadgeLabel.Size = UDim2.new(1, 0, 1, 0); Core.UI.stateBadgeLabel.BackgroundTransparency = 1; Core.UI.stateBadgeLabel.Text = "IDLE"; Core.UI.stateBadgeLabel.TextColor3 = Color3.fromRGB(220, 225, 235); Core.UI.stateBadgeLabel.TextSize = 9; Core.UI.stateBadgeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); Core.UI.stateBadgeLabel.Parent = Core.UI.stateBadge

Core.updateStateBadge = function(stateName, color)
    Core.UI.stateBadgeLabel.Text = stateName
    Core.UI.hudBadgeLabel.Text = stateName
    TweenService:Create(Core.UI.stateBadge, TWEEN_QUICK, { BackgroundColor3 = color }):Play()
    TweenService:Create(Core.UI.hudBadge, TWEEN_QUICK, { BackgroundColor3 = color }):Play()
end

local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(1, 0, 0, 12); subLabel.BackgroundTransparency = 1; subLabel.Text = "MASTER KINEMATIC SUITE"
subLabel.TextColor3 = activeTheme.Accent; subLabel.TextSize = 10; subLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); subLabel.TextXAlignment = Enum.TextXAlignment.Left; subLabel.Parent = titleGroup
registerElement("AccentText", subLabel, "TextColor3")

local headerBtnGroup = Instance.new("Frame")
headerBtnGroup.Size = UDim2.new(0, 64, 1, 0); headerBtnGroup.Position = UDim2.new(1, -74, 0, 0); headerBtnGroup.BackgroundTransparency = 1; headerBtnGroup.Parent = header
local hBtnLayout = Instance.new("UIListLayout"); hBtnLayout.FillDirection = Enum.FillDirection.Horizontal; hBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right; hBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center; hBtnLayout.Padding = UDim.new(0, 6); hBtnLayout.Parent = headerBtnGroup

local isMinimized = false
local unminimizedHeight = 520
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28); minBtn.BackgroundColor3 = activeTheme.Surface; minBtn.BackgroundTransparency = 0.6; minBtn.BorderSizePixel = 0; minBtn.AutoButtonColor = false; minBtn.Text = "—"; minBtn.TextColor3 = activeTheme.TextSecondary; minBtn.TextSize = 13; minBtn.Parent = headerBtnGroup
local minCorner = Instance.new("UICorner"); minCorner.CornerRadius = UDim.new(0, 6); minCorner.Parent = minBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28); closeBtn.BackgroundColor3 = activeTheme.Surface; closeBtn.BackgroundTransparency = 0.6; closeBtn.BorderSizePixel = 0; closeBtn.AutoButtonColor = false; closeBtn.Text = "×"; closeBtn.TextColor3 = activeTheme.TextSecondary; closeBtn.TextSize = 20; closeBtn.Parent = headerBtnGroup
local closeCorner = Instance.new("UICorner"); closeCorner.CornerRadius = UDim.new(0, 6); closeCorner.Parent = closeBtn

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        unminimizedHeight = Core.UI.mainFrame.AbsoluteSize.Y
        TweenService:Create(Core.UI.mainFrame, TWEEN_QUICK, { Size = UDim2.new(0, Core.UI.mainFrame.AbsoluteSize.X, 0, 48) }):Play()
    else
        TweenService:Create(Core.UI.mainFrame, TWEEN_QUICK, { Size = UDim2.new(0, Core.UI.mainFrame.AbsoluteSize.X, 0, unminimizedHeight) }):Play()
    end
end)

local isGuiOpen = true
local function setGuiVisible(visible)
    isGuiOpen = visible
    if visible then
        Core.UI.mainFrame.Visible = true; Core.UI.mainFrame.BackgroundTransparency = 1
        TweenService:Create(Core.UI.mainFrame, TWEEN_QUICK, { BackgroundTransparency = 0.15 }):Play()
    else
        local closeTween = TweenService:Create(Core.UI.mainFrame, TWEEN_QUICK, { BackgroundTransparency = 1 })
        closeTween:Play()
        closeTween.Completed:Connect(function() if not isGuiOpen then Core.UI.mainFrame.Visible = false end end)
    end
end
closeBtn.MouseButton1Click:Connect(function() setGuiVisible(false) end)

local progressTrack = Instance.new("Frame")
progressTrack.Size = UDim2.new(1, 0, 0, 2); progressTrack.Position = UDim2.new(0, 0, 0, 48); progressTrack.BackgroundColor3 = activeTheme.Border; progressTrack.BorderSizePixel = 0; progressTrack.Parent = Core.UI.mainFrame

Core.UI.progressBar = Instance.new("Frame")
Core.UI.progressBar.Size = UDim2.new(0, 0, 1, 0); Core.UI.progressBar.BackgroundColor3 = activeTheme.Accent; Core.UI.progressBar.BorderSizePixel = 0; Core.UI.progressBar.Parent = progressTrack
registerElement("AccentBg", Core.UI.progressBar, "BackgroundColor3")

Core.UI.toastFrame = Instance.new("Frame")
Core.UI.toastFrame.Size = UDim2.new(1, -28, 0, 32); Core.UI.toastFrame.Position = UDim2.new(0, 14, 1, 40); Core.UI.toastFrame.BackgroundColor3 = activeTheme.Surface; Core.UI.toastFrame.BorderSizePixel = 0; Core.UI.toastFrame.ZIndex = 20; Core.UI.toastFrame.Parent = Core.UI.mainFrame
local toastCorner = Instance.new("UICorner"); toastCorner.CornerRadius = UDim.new(0, 6); toastCorner.Parent = Core.UI.toastFrame

Core.UI.toastLabel = Instance.new("TextLabel")
Core.UI.toastLabel.Size = UDim2.new(1, -16, 1, 0); Core.UI.toastLabel.Position = UDim2.new(0, 8, 0, 0); Core.UI.toastLabel.BackgroundTransparency = 1; Core.UI.toastLabel.Text = "Notification"; Core.UI.toastLabel.TextColor3 = activeTheme.TextPrimary; Core.UI.toastLabel.TextSize = 11; Core.UI.toastLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); Core.UI.toastLabel.ZIndex = 21; Core.UI.toastLabel.Parent = Core.UI.toastFrame
registerElement("TextPrimary", Core.UI.toastLabel, "TextColor3")

local toastSerial = 0
Core.showToast = function(message)
    Core.UI.toastLabel.Text = message; toastSerial = toastSerial + 1; local mySerial = toastSerial
    task.spawn(function()
        TweenService:Create(Core.UI.toastFrame, TWEEN_BOUNCE, { Position = UDim2.new(0, 14, 1, -44) }):Play()
        task.wait(2.2)
        if toastSerial == mySerial then TweenService:Create(Core.UI.toastFrame, TWEEN_QUICK, { Position = UDim2.new(0, 14, 1, 40) }):Play() end
    end)
end

local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, 0, 0, 36); tabContainer.Position = UDim2.new(0, 0, 0, 50); tabContainer.BackgroundColor3 = activeTheme.Surface; tabContainer.BackgroundTransparency = 0.6; tabContainer.BorderSizePixel = 0; tabContainer.Parent = Core.UI.mainFrame
local tabLayout = Instance.new("UIListLayout"); tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.SortOrder = Enum.SortOrder.LayoutOrder; tabLayout.Padding = UDim.new(0, 8); tabLayout.Parent = tabContainer
local tabPadding = Instance.new("UIPadding"); tabPadding.PaddingLeft = UDim.new(0, 12); tabPadding.PaddingRight = UDim.new(0, 12); tabPadding.Parent = tabContainer

local pages = {}
local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, 0, 1, -86); page.Position = UDim2.new(0, 0, 0, 86); page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 3; page.ScrollBarImageColor3 = activeTheme.Border; page.CanvasSize = UDim2.new(0, 0, 0, 0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = false; page.Parent = Core.UI.mainFrame
    local pPadding = Instance.new("UIPadding"); pPadding.PaddingTop = UDim.new(0, 10); pPadding.PaddingBottom = UDim.new(0, 16); pPadding.PaddingLeft = UDim.new(0, 14); pPadding.PaddingRight = UDim.new(0, 14); pPadding.Parent = page
    local pList = Instance.new("UIListLayout"); pList.SortOrder = Enum.SortOrder.LayoutOrder; pList.Padding = UDim.new(0, 8); pList.Parent = page
    pages[name] = page
    return page
end

local controlsPage = createPage("Controls")
local settingsPage = createPage("Settings")
local advancedPage = createPage("Advanced")
local safetyPage = createPage("Safety")
controlsPage.Visible = true

local tabButtons = {}
local function createTabButton(name, targetPage, isDefault)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(0, 72, 1, 0); tabBtn.BackgroundTransparency = 1; tabBtn.Text = name; tabBtn.TextColor3 = isDefault and activeTheme.Accent or activeTheme.TextSecondary; tabBtn.TextSize = 11; tabBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); tabBtn.Parent = tabContainer
    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(1, 0, 0, 2); indicator.Position = UDim2.new(0, 0, 1, -2); indicator.BackgroundColor3 = activeTheme.Accent; indicator.BackgroundTransparency = isDefault and 0 or 1; indicator.BorderSizePixel = 0; indicator.Parent = tabBtn

    tabButtons[name] = { Button = tabBtn, Indicator = indicator, Page = targetPage }
    tabBtn.MouseButton1Click:Connect(function()
        for tabName, data in pairs(tabButtons) do
            local active = (tabName == name)
            data.Page.Visible = active
            TweenService:Create(data.Button, TWEEN_QUICK, { TextColor3 = active and activeTheme.Accent or activeTheme.TextSecondary }):Play()
            TweenService:Create(data.Indicator, TWEEN_QUICK, { BackgroundTransparency = active and 0 or 1 }):Play()
        end
    end)
end

createTabButton("Controls", controlsPage, true)
createTabButton("Settings", settingsPage, false)
createTabButton("Advanced", advancedPage, false)
createTabButton("Safety", safetyPage, false)

local function createToggleRow(parent, name, labelText, activeColor, onToggled, order, defaultState)
    local row = Instance.new("Frame")
    row.LayoutOrder = order; row.Size = UDim2.new(1, 0, 0, 42); row.BackgroundColor3 = activeTheme.Surface; row.BackgroundTransparency = 0.5; row.BorderSizePixel = 0; row.Parent = parent
    local rowCorner = Instance.new("UICorner"); rowCorner.CornerRadius = UDim.new(0, 8); rowCorner.Parent = row
    local rowStroke = Instance.new("UIStroke"); rowStroke.Thickness = 1; rowStroke.Color = activeTheme.Border; rowStroke.Transparency = 0.5; rowStroke.Parent = row
    local rowPadding = Instance.new("UIPadding"); rowPadding.PaddingLeft = UDim.new(0, 14); rowPadding.PaddingRight = UDim.new(0, 14); rowPadding.Parent = row
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0); label.BackgroundTransparency = 1; label.Text = labelText; label.TextColor3 = activeTheme.TextPrimary; label.TextSize = 12; label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = row

    local switchTrack = Instance.new("TextButton")
    switchTrack.Size = UDim2.new(0, 42, 0, 22); switchTrack.Position = UDim2.new(1, -42, 0.5, -11); switchTrack.BackgroundColor3 = defaultState and activeColor or activeTheme.ToggleOff; switchTrack.BackgroundTransparency = 0.2; switchTrack.BorderSizePixel = 0; switchTrack.AutoButtonColor = false; switchTrack.Text = ""; switchTrack.Parent = row
    local trackCorner = Instance.new("UICorner"); trackCorner.CornerRadius = UDim.new(1, 0); trackCorner.Parent = switchTrack

    local switchKnob = Instance.new("Frame")
    switchKnob.Size = UDim2.new(0, 16, 0, 16); switchKnob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8); switchKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); switchKnob.BorderSizePixel = 0; switchKnob.Parent = switchTrack
    local knobCorner = Instance.new("UICorner"); knobCorner.CornerRadius = UDim.new(1, 0); knobCorner.Parent = switchKnob

    local isToggled = defaultState or false
    local isInternalSetting = false

    local function setToggleState(state, suppressCallback)
        if isInternalSetting then return end
        isToggled = state
        TweenService:Create(switchTrack, TWEEN_QUICK, { BackgroundColor3 = isToggled and activeColor or activeTheme.ToggleOff }):Play()
        TweenService:Create(switchKnob, TWEEN_BOUNCE, { Position = isToggled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8) }):Play()
        TweenService:Create(rowStroke, TWEEN_QUICK, { Color = isToggled and activeColor or activeTheme.Border }):Play()

        if not suppressCallback and typeof(onToggled) == "function" then
            isInternalSetting = true; pcall(function() onToggled(isToggled) end); isInternalSetting = false
        end
    end

    switchTrack.MouseButton1Click:Connect(function() setToggleState(not isToggled) end)
    return { Set = setToggleState, Get = function() return isToggled end }
end

local function createActionButton(parent, labelText, order, onClick, customColor)
    local btn = Instance.new("TextButton")
    btn.LayoutOrder = order; btn.Size = UDim2.new(1, 0, 0, 36); btn.BackgroundColor3 = customColor or activeTheme.Surface; btn.BackgroundTransparency = customColor and 0.25 or 0.4; btn.BorderSizePixel = 0; btn.AutoButtonColor = false; btn.Text = labelText; btn.TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary; btn.TextSize = 12; btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); btn.Parent = parent
    local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 8); btnCorner.Parent = btn
    local btnStroke = Instance.new("UIStroke"); btnStroke.Thickness = 1; btnStroke.Color = customColor or activeTheme.Border; btnStroke.Transparency = 0.5; btnStroke.Parent = btn

    btn.MouseEnter:Connect(function() TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Border, TextColor3 = Color3.fromRGB(255, 255, 255) }):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Surface, TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary }):Play() end)
    btn.MouseButton1Click:Connect(function()
        local flash = TweenService:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = activeTheme.Accent, TextColor3 = Color3.fromRGB(255, 255, 255) })
        flash:Play()
        flash.Completed:Connect(function() TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Surface, TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary }):Play() end)
        if typeof(onClick) == "function" then onClick() end
    end)
    return btn
end

local function createSliderRow(parent, name, labelText, minVal, maxVal, defaultVal, formatStr, onValueChanged, order)
    local row = Instance.new("Frame")
    row.LayoutOrder = order; row.Size = UDim2.new(1, 0, 0, 48); row.BackgroundColor3 = activeTheme.Surface; row.BackgroundTransparency = 0.5; row.BorderSizePixel = 0; row.Parent = parent
    local rowCorner = Instance.new("UICorner"); rowCorner.CornerRadius = UDim.new(0, 8); rowCorner.Parent = row
    local rowStroke = Instance.new("UIStroke"); rowStroke.Thickness = 1; rowStroke.Color = activeTheme.Border; rowStroke.Transparency = 0.5; rowStroke.Parent = row
    local rowPadding = Instance.new("UIPadding"); rowPadding.PaddingLeft = UDim.new(0, 14); rowPadding.PaddingRight = UDim.new(0, 14); rowPadding.Parent = row

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0.6, 0, 0, 20); titleLbl.Position = UDim2.new(0, 0, 0, 6); titleLbl.BackgroundTransparency = 1; titleLbl.Text = labelText; titleLbl.TextColor3 = activeTheme.TextPrimary; titleLbl.TextSize = 12; titleLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.4, 0, 0, 20); valLbl.Position = UDim2.new(0.6, 0, 0, 6); valLbl.BackgroundTransparency = 1; valLbl.Text = (formatStr == "Loops: %d" and defaultVal == 0) and "Loops: Inf" or string.format(formatStr, defaultVal); valLbl.TextColor3 = activeTheme.Accent; valLbl.TextSize = 12; valLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.Parent = row

    local sliderBar = Instance.new("Frame")
    sliderBar.Size = UDim2.new(1, 0, 0, 6); sliderBar.Position = UDim2.new(0, 0, 1, -14); sliderBar.BackgroundColor3 = activeTheme.ToggleOff; sliderBar.BorderSizePixel = 0; sliderBar.Parent = row
    local sCorner = Instance.new("UICorner"); sCorner.CornerRadius = UDim.new(1, 0); sCorner.Parent = sliderBar

    local fillBar = Instance.new("Frame")
    local initRatio = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    fillBar.Size = UDim2.new(initRatio, 0, 1, 0); fillBar.BackgroundColor3 = activeTheme.Accent; fillBar.BorderSizePixel = 0; fillBar.Parent = sliderBar
    local fCorner = Instance.new("UICorner"); fCorner.CornerRadius = UDim.new(1, 0); fCorner.Parent = fillBar

    local draggingSlider = false
    local function updateValue(inputX)
        local relX = math.clamp(inputX - sliderBar.AbsolutePosition.X, 0, sliderBar.AbsoluteSize.X)
        local ratio = relX / sliderBar.AbsoluteSize.X
        local calcVal = minVal + (maxVal - minVal) * ratio
        if string.find(formatStr, "%%d") then
            calcVal = math.floor(calcVal)
            valLbl.Text = (formatStr == "Loops: %d" and calcVal == 0) and "Loops: Inf" or string.format(formatStr, calcVal)
        else
            valLbl.Text = string.format(formatStr, calcVal)
        end
        fillBar.Size = UDim2.new(ratio, 0, 1, 0)
        if typeof(onValueChanged) == "function" then onValueChanged(calcVal) end
    end

    sliderBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true; updateValue(input.Position.X)
        end
    end)
    local moveConn = UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateValue(input.Position.X)
        end
    end)
    table.insert(Core.scriptConnections, moveConn)
    local endConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = false end
    end)
    table.insert(Core.scriptConnections, endConn)

    return row
end

local function createSectionHeader(parent, titleText, order)
    local secHeader = Instance.new("TextLabel")
    secHeader.LayoutOrder = order; secHeader.Size = UDim2.new(1, 0, 0, 20); secHeader.BackgroundTransparency = 1; secHeader.Text = string.upper(titleText); secHeader.TextColor3 = activeTheme.Accent; secHeader.TextSize = 10; secHeader.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); secHeader.TextXAlignment = Enum.TextXAlignment.Left; secHeader.Parent = parent
    return secHeader
end

local telemetryCard = Instance.new("Frame")
telemetryCard.LayoutOrder = 1; telemetryCard.Size = UDim2.new(1, 0, 0, 44); telemetryCard.BackgroundColor3 = activeTheme.Surface; telemetryCard.BackgroundTransparency = 0.35; telemetryCard.BorderSizePixel = 0; telemetryCard.Parent = controlsPage
local tCardCorner = Instance.new("UICorner"); tCardCorner.CornerRadius = UDim.new(0, 8); tCardCorner.Parent = telemetryCard
local tCardStroke = Instance.new("UIStroke"); tCardStroke.Thickness = 1; tCardStroke.Color = activeTheme.Border; tCardStroke.Transparency = 0.4; tCardStroke.Parent = telemetryCard
local tCardPadding = Instance.new("UIPadding"); tCardPadding.PaddingLeft = UDim.new(0, 14); tCardPadding.PaddingRight = UDim.new(0, 14); tCardPadding.Parent = telemetryCard

Core.UI.nodeStatsLabel = Instance.new("TextLabel")
Core.UI.nodeStatsLabel.Size = UDim2.new(0.58, -4, 1, 0); Core.UI.nodeStatsLabel.Position = UDim2.new(0, 0, 0, 0); Core.UI.nodeStatsLabel.BackgroundTransparency = 1; Core.UI.nodeStatsLabel.Text = "Waypoints: 0 | Loop: 0/Inf"; Core.UI.nodeStatsLabel.TextColor3 = activeTheme.TextPrimary; Core.UI.nodeStatsLabel.TextSize = 11; Core.UI.nodeStatsLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); Core.UI.nodeStatsLabel.TextXAlignment = Enum.TextXAlignment.Left; Core.UI.nodeStatsLabel.Parent = telemetryCard

Core.UI.routeModeLabel = Instance.new("TextLabel")
Core.UI.routeModeLabel.Size = UDim2.new(0.42, -4, 1, 0); Core.UI.routeModeLabel.Position = UDim2.new(0.58, 4, 0, 0); Core.UI.routeModeLabel.BackgroundTransparency = 1; Core.UI.routeModeLabel.Text = "Mode: Loop (1.00x)"; Core.UI.routeModeLabel.TextColor3 = activeTheme.Accent; Core.UI.routeModeLabel.TextSize = 11; Core.UI.routeModeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); Core.UI.routeModeLabel.TextXAlignment = Enum.TextXAlignment.Right; Core.UI.routeModeLabel.Parent = telemetryCard

Core.UI.recordToggleControl = createToggleRow(controlsPage, "RecordToggle", "Record Route Path", activeTheme.RecordActive, function(state) if state then Core.startRecording() else Core.stopRecording() end end, 2)
Core.UI.playToggleControl = createToggleRow(controlsPage, "PlayToggle", "Execute Playback Route", activeTheme.PlayActive, function(state) if state then Core.startPlayback() else Core.stopPlayback() end end, 3)

local fileRow = Instance.new("Frame")
fileRow.LayoutOrder = 4; fileRow.Size = UDim2.new(1, 0, 0, 42); fileRow.BackgroundColor3 = activeTheme.Surface; fileRow.BackgroundTransparency = 0.5; fileRow.BorderSizePixel = 0; fileRow.Parent = controlsPage
local fileCorner = Instance.new("UICorner"); fileCorner.CornerRadius = UDim.new(0, 8); fileCorner.Parent = fileRow
local fileStroke = Instance.new("UIStroke"); fileStroke.Thickness = 1; fileStroke.Color = activeTheme.Border; fileStroke.Transparency = 0.5; fileStroke.Parent = fileRow

local fileInput = Instance.new("TextBox")
fileInput.Size = UDim2.new(1, -156, 1, 0); fileInput.Position = UDim2.new(0, 10, 0, 0); fileInput.BackgroundTransparency = 1; fileInput.Text = "ManniskaFarm_Route.json"; fileInput.PlaceholderText = "RouteFileName.json"; fileInput.TextColor3 = activeTheme.TextPrimary; fileInput.TextSize = 12; fileInput.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); fileInput.TextXAlignment = Enum.TextXAlignment.Left; fileInput.ClearTextOnFocus = false; fileInput.Parent = fileRow

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(0, 64, 0, 26); saveBtn.Position = UDim2.new(1, -138, 0.5, -13); saveBtn.BackgroundColor3 = activeTheme.Border; saveBtn.BackgroundTransparency = 0.3; saveBtn.BorderSizePixel = 0; saveBtn.Text = "Save"; saveBtn.TextColor3 = activeTheme.TextPrimary; saveBtn.TextSize = 11; saveBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); saveBtn.Parent = fileRow
local saveCorner = Instance.new("UICorner"); saveCorner.CornerRadius = UDim.new(0, 6); saveCorner.Parent = saveBtn
saveBtn.MouseButton1Click:Connect(function() Core.saveRouteToFile(fileInput.Text) end)

local loadBtn = Instance.new("TextButton")
loadBtn.Size = UDim2.new(0, 64, 0, 26); loadBtn.Position = UDim2.new(1, -68, 0.5, -13); loadBtn.BackgroundColor3 = activeTheme.Accent; loadBtn.BackgroundTransparency = 0.2; loadBtn.BorderSizePixel = 0; loadBtn.Text = "Load"; loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255); loadBtn.TextSize = 11; loadBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); loadBtn.Parent = fileRow
local loadCorner = Instance.new("UICorner"); loadCorner.CornerRadius = UDim.new(0, 6); loadCorner.Parent = loadBtn
loadBtn.MouseButton1Click:Connect(function() Core.loadRouteFromFile(fileInput.Text) end)

local dropdownCard = Instance.new("Frame")
dropdownCard.LayoutOrder = 5; dropdownCard.Size = UDim2.new(1, 0, 0, 72); dropdownCard.BackgroundColor3 = activeTheme.Surface; dropdownCard.BackgroundTransparency = 0.6; dropdownCard.BorderSizePixel = 0; dropdownCard.Parent = controlsPage
local ddCorner = Instance.new("UICorner"); ddCorner.CornerRadius = UDim.new(0, 8); ddCorner.Parent = dropdownCard
local ddStroke = Instance.new("UIStroke"); ddStroke.Thickness = 1; ddStroke.Color = activeTheme.Border; ddStroke.Transparency = 0.5; ddStroke.Parent = dropdownCard

local ddList = Instance.new("ScrollingFrame")
ddList.Size = UDim2.new(1, -12, 1, -8); ddList.Position = UDim2.new(0, 6, 0, 4); ddList.BackgroundTransparency = 1; ddList.BorderSizePixel = 0; ddList.ScrollBarThickness = 2; ddList.ScrollBarImageColor3 = activeTheme.Accent; ddList.CanvasSize = UDim2.new(0, 0, 0, 0); ddList.AutomaticCanvasSize = Enum.AutomaticSize.Y; ddList.Parent = dropdownCard
local ddLayout = Instance.new("UIListLayout"); ddLayout.SortOrder = Enum.SortOrder.LayoutOrder; ddLayout.Padding = UDim.new(0, 4); ddLayout.Parent = ddList

local function refreshFileList()
    for _, child in ipairs(ddList:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    local files = (listfiles and typeof(listfiles) == "function") and listfiles("") or { "ManniskaFarm_Route.json" }
    for _, path in ipairs(files) do
        if string.find(path, ".json") then
            local cleanName = string.gsub(path, "^.*[\\/]", "")
            local fBtn = Instance.new("TextButton")
            fBtn.Size = UDim2.new(1, 0, 0, 22); fBtn.BackgroundColor3 = activeTheme.ToggleOff; fBtn.BackgroundTransparency = 0.4; fBtn.BorderSizePixel = 0; fBtn.Text = "   📁 " .. cleanName; fBtn.TextColor3 = activeTheme.TextPrimary; fBtn.TextSize = 10; fBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); fBtn.TextXAlignment = Enum.TextXAlignment.Left; fBtn.Parent = ddList
            local fCorner = Instance.new("UICorner"); fCorner.CornerRadius = UDim.new(0, 4); fCorner.Parent = fBtn
            fBtn.MouseButton1Click:Connect(function() fileInput.Text = cleanName; Core.loadRouteFromFile(cleanName) end)
        end
    end
end
refreshFileList()

createActionButton(controlsPage, "Undo Last Node (Z)", 6, function() Core.undoLastNode() end)
createActionButton(controlsPage, "Copy JSON to Clipboard", 7, function() Core.copyRouteToClipboard() end)
createActionButton(controlsPage, "Clear Path Waypoints", 8, function() Core.clearWaypoints() end)

createSectionHeader(settingsPage, "Playback & Scaling", 1)

local modeRow = Instance.new("Frame")
modeRow.LayoutOrder = 2; modeRow.Size = UDim2.new(1, 0, 0, 42); modeRow.BackgroundColor3 = activeTheme.Surface; modeRow.BackgroundTransparency = 0.5; modeRow.BorderSizePixel = 0; modeRow.Parent = settingsPage
local modeCorner = Instance.new("UICorner"); modeCorner.CornerRadius = UDim.new(0, 8); modeCorner.Parent = modeRow
local modeStroke = Instance.new("UIStroke"); modeStroke.Thickness = 1; modeStroke.Color = activeTheme.Border; modeStroke.Transparency = 0.5; modeStroke.Parent = modeRow
local modePadding = Instance.new("UIPadding"); modePadding.PaddingLeft = UDim.new(0, 14); modePadding.PaddingRight = UDim.new(0, 14); modePadding.Parent = modeRow

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(1, -120, 1, 0); modeLabel.BackgroundTransparency = 1; modeLabel.Text = "Playback Route Mode"; modeLabel.TextColor3 = activeTheme.TextPrimary; modeLabel.TextSize = 12; modeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); modeLabel.TextXAlignment = Enum.TextXAlignment.Left; modeLabel.Parent = modeRow

local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0, 100, 0, 26); modeBtn.Position = UDim2.new(1, -100, 0.5, -13); modeBtn.BackgroundColor3 = activeTheme.ToggleOff; modeBtn.BackgroundTransparency = 0.2; modeBtn.BorderSizePixel = 0; modeBtn.Text = Config.PlaybackMode; modeBtn.TextColor3 = activeTheme.Accent; modeBtn.TextSize = 11; modeBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); modeBtn.Parent = modeRow
local modeBtnCorner = Instance.new("UICorner"); modeBtnCorner.CornerRadius = UDim.new(0, 6); modeBtnCorner.Parent = modeBtn

local modes = { "Loop", "Ping-Pong", "One-Shot", "Reverse" }
local modeIdx = 1
modeBtn.MouseButton1Click:Connect(function()
    modeIdx = (modeIdx % #modes) + 1
    Config.PlaybackMode = modes[modeIdx]
    modeBtn.Text = Config.PlaybackMode
    Core.updateTelemetry(nil, #Core.Waypoints)
end)

createSliderRow(settingsPage, "LoopSlider", "Loop Count Limit", 0, 200, Config.TargetLoops, "Loops: %d", function(val) Config.TargetLoops = math.floor(val); Core.updateTelemetry(nil, #Core.Waypoints) end, 3)
createSliderRow(settingsPage, "SpeedSlider", "Playback Speed", 0.5, 3.0, Config.SpeedMultiplier, "%.2fx", function(val) Config.SpeedMultiplier = math.floor(val * 100) / 100; Core.updateTelemetry(nil, #Core.Waypoints) end, 4)

createSectionHeader(settingsPage, "Hardware Bridge & Integration", 5)
createToggleRow(settingsPage, "BridgeToggle", "External Macro Bridge (.NET)", activeTheme.PlayActive, function(state) Config.UseExternalBridge = state; Core.showToast("Hardware Bridge: " .. (state and "Enabled" or "Disabled")) end, 6, Config.UseExternalBridge)

createSectionHeader(settingsPage, "Display & Visualizer", 7)
createToggleRow(settingsPage, "StatusHUDToggle", "Persistent Status Bar (Draggable)", activeTheme.Accent, function(state) Config.StatusHUDEnabled = state; Core.UI.statusHUD.Visible = state end, 8, Config.StatusHUDEnabled)
createToggleRow(settingsPage, "RealtimeVisToggle", "Realtime Visual Rendering", activeTheme.Accent, function(state) Config.RealtimeVisualizer = state end, 9, Config.RealtimeVisualizer)
createToggleRow(settingsPage, "WaypointLabelsToggle", "3D Waypoint Tags", activeTheme.Accent, function(state) Config.WaypointLabelsEnabled = state; Core.renderVisualPath(Core.Waypoints) end, 10, Config.WaypointLabelsEnabled)
createToggleRow(settingsPage, "VisualizerToggle", "3D Workspace Visualizer", activeTheme.Accent, function(state) Config.VisualizerEnabled = state; if state then Core.renderVisualPath(Core.Waypoints) else Core.clearVisuals() end end, 11, Config.VisualizerEnabled)
createSliderRow(settingsPage, "OrbOpacitySlider", "Visualizer Orb Opacity", 0.0, 0.8, Config.VisualizerOpacity, "Opacity: %.2f", function(val) Config.VisualizerOpacity = math.floor(val * 100) / 100; Core.renderVisualPath(Core.Waypoints) end, 12)

createSectionHeader(settingsPage, "Keybind Shortcuts", 13)
local activeBindingKey = nil
local function createKeybindRow(labelText, actionKeyName, order)
    local row = Instance.new("Frame")
    row.LayoutOrder = order; row.Size = UDim2.new(1, 0, 0, 42); row.BackgroundColor3 = activeTheme.Surface; row.BackgroundTransparency = 0.5; row.BorderSizePixel = 0; row.Parent = settingsPage
    local kCorner = Instance.new("UICorner"); kCorner.CornerRadius = UDim.new(0, 8); kCorner.Parent = row
    local kStroke = Instance.new("UIStroke"); kStroke.Thickness = 1; kStroke.Color = activeTheme.Border; kStroke.Transparency = 0.5; kStroke.Parent = row
    local kPadding = Instance.new("UIPadding"); kPadding.PaddingLeft = UDim.new(0, 14); kPadding.PaddingRight = UDim.new(0, 14); kPadding.Parent = row

    local kLabel = Instance.new("TextLabel")
    kLabel.Size = UDim2.new(1, -120, 1, 0); kLabel.BackgroundTransparency = 1; kLabel.Text = labelText; kLabel.TextColor3 = activeTheme.TextPrimary; kLabel.TextSize = 12; kLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium); kLabel.TextXAlignment = Enum.TextXAlignment.Left; kLabel.Parent = row

    local kBtn = Instance.new("TextButton")
    kBtn.Size = UDim2.new(0, 100, 0, 26); kBtn.Position = UDim2.new(1, -100, 0.5, -13); kBtn.BackgroundColor3 = activeTheme.ToggleOff; kBtn.BackgroundTransparency = 0.2; kBtn.BorderSizePixel = 0; kBtn.AutoButtonColor = false; kBtn.Text = Keybinds[actionKeyName].Name; kBtn.TextColor3 = activeTheme.TextPrimary; kBtn.TextSize = 11; kBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); kBtn.Parent = row
    local kBtnCorner = Instance.new("UICorner"); kBtnCorner.CornerRadius = UDim.new(0, 6); kBtnCorner.Parent = kBtn

    kBtn.MouseButton1Click:Connect(function()
        if activeBindingKey then return end
        activeBindingKey = actionKeyName
        kBtn.Text = "Press Key..."
        kBtn.TextColor3 = activeTheme.Accent
    end)
    return { KeyName = actionKeyName, Button = kBtn }
end

local bindMenu = createKeybindRow("Toggle Menu", "ToggleMenu", 14)
local bindRec = createKeybindRow("Record Route", "ToggleRecord", 15)
local bindPlay = createKeybindRow("Play Route", "TogglePlay", 16)
local bindUndo = createKeybindRow("Undo Node", "UndoNode", 17)

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if activeBindingKey and input.UserInputType == Enum.UserInputType.Keyboard then
        Keybinds[activeBindingKey] = input.KeyCode
        if activeBindingKey == "ToggleMenu" then bindMenu.Button.Text = input.KeyCode.Name; bindMenu.Button.TextColor3 = activeTheme.TextPrimary end
        if activeBindingKey == "ToggleRecord" then bindRec.Button.Text = input.KeyCode.Name; bindRec.Button.TextColor3 = activeTheme.TextPrimary end
        if activeBindingKey == "TogglePlay" then bindPlay.Button.Text = input.KeyCode.Name; bindPlay.Button.TextColor3 = activeTheme.TextPrimary end
        if activeBindingKey == "UndoNode" then bindUndo.Button.Text = input.KeyCode.Name; bindUndo.Button.TextColor3 = activeTheme.TextPrimary end
        Core.showToast(string.format("%s set to: %s", activeBindingKey, input.KeyCode.Name))
        activeBindingKey = nil
        return
    end

    if not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Keybinds.ToggleMenu then setGuiVisible(not isGuiOpen)
        elseif input.KeyCode == Keybinds.ToggleRecord then if Core.UI.recordToggleControl and typeof(Core.UI.recordToggleControl.Get) == "function" then Core.UI.recordToggleControl.Set(not Core.UI.recordToggleControl.Get()) end
        elseif input.KeyCode == Keybinds.TogglePlay then if Core.UI.playToggleControl and typeof(Core.UI.playToggleControl.Get) == "function" then Core.UI.playToggleControl.Set(not Core.UI.playToggleControl.Get()) end
        elseif input.KeyCode == Keybinds.UndoNode then Core.undoLastNode() end
    end
end)
table.insert(Core.scriptConnections, inputConnection)

createSectionHeader(advancedPage, "Humanization & Randomization", 1)
createToggleRow(advancedPage, "MicroRandToggle", "Micro Randomization (Human Timing)", activeTheme.Accent, function(state) Config.MicroRandomization = state end, 2, Config.MicroRandomization)

createSectionHeader(advancedPage, "Kinematic Modifiers", 3)
createToggleRow(advancedPage, "AutoTeleportToggle", "Auto-Teleport (CFrame Skip)", activeTheme.Accent, function(state) Config.AutoTeleport = state end, 4, Config.AutoTeleport)
createToggleRow(advancedPage, "FallDamperToggle", "Fall Damper (Anti-Fall Damage)", activeTheme.Accent, function(state) Config.FallDamper = state end, 5, Config.FallDamper)
createToggleRow(advancedPage, "SpeedCurvesToggle", "Speed Curves (Record Sprinting)", activeTheme.Accent, function(state) Config.SpeedCurves = state end, 6, Config.SpeedCurves)

createSectionHeader(advancedPage, "Input Recording", 13)
createToggleRow(advancedPage, "RecordClicksToggle", "Record Mouse Clicks (MB1)", activeTheme.Accent, function(state) Config.RecordMouseClicks = state end, 14, Config.RecordMouseClicks)

createSectionHeader(safetyPage, "Player Proximity Radar", 1)
createToggleRow(safetyPage, "RadarToggle", "Enable Player Radar", Color3.fromRGB(240, 70, 70), function(state) Config.ProximityRadar = state end, 2, Config.ProximityRadar)
createSliderRow(safetyPage, "RadarRadiusSlider", "Radar Detection Radius", 20, 150, Config.RadarRadius, "%d Studs", function(val) Config.RadarRadius = math.floor(val) end, 3)

createSectionHeader(safetyPage, "Account & Session Protection", 5)
createToggleRow(safetyPage, "LeaveOnDeathToggle", "Emergency Leave on Death", Color3.fromRGB(240, 70, 70), function(state) Config.EmergencyLeaveOnDeath = state end, 6, Config.EmergencyLeaveOnDeath)
createToggleRow(safetyPage, "AntiAFKToggle", "Anti-AFK Protection", activeTheme.Accent, function(state) Config.AntiAFKEnabled = state end, 7, Config.AntiAFKEnabled)
createToggleRow(safetyPage, "UnstuckToggle", "Smart Stuck Recovery", activeTheme.PlayActive, function(state) Config.AutoUnstuckEnabled = state end, 8, Config.AutoUnstuckEnabled)

createSectionHeader(safetyPage, "Process Lifecycle", 9)
local terminateBtn = Instance.new("TextButton")
terminateBtn.LayoutOrder = 10; terminateBtn.Size = UDim2.new(1, 0, 0, 38); terminateBtn.BackgroundColor3 = Color3.fromRGB(45, 20, 24); terminateBtn.BackgroundTransparency = 0.3; terminateBtn.BorderSizePixel = 0; terminateBtn.Text = "Terminate & Unload Script"; terminateBtn.TextColor3 = Color3.fromRGB(255, 95, 95); terminateBtn.TextSize = 12; terminateBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold); terminateBtn.Parent = safetyPage
local termCorner = Instance.new("UICorner"); termCorner.CornerRadius = UDim.new(0, 8); termCorner.Parent = terminateBtn
local termStroke = Instance.new("UIStroke"); termStroke.Thickness = 1.2; termStroke.Color = Color3.fromRGB(240, 70, 70); termStroke.Transparency = 0.4; termStroke.Parent = terminateBtn
terminateBtn.MouseButton1Click:Connect(function() Core.terminateProcess() end)

local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 18, 0, 18); resizeHandle.Position = UDim2.new(1, -18, 1, -18); resizeHandle.BackgroundTransparency = 1; resizeHandle.Text = "◢"; resizeHandle.TextColor3 = activeTheme.TextSecondary; resizeHandle.Parent = Core.UI.mainFrame

local dragging, dragStartPos, frameStartPos = false, nil, nil
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStartPos = input.Position; frameStartPos = Core.UI.mainFrame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
local dragChangeConn = UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartPos
        Core.UI.mainFrame.Position = UDim2.new(frameStartPos.X.Scale, frameStartPos.X.Offset + delta.X, frameStartPos.Y.Scale, frameStartPos.Y.Offset + delta.Y)
    end
end)
table.insert(Core.scriptConnections, dragChangeConn)

-- =====================================================================
--  CORE LOGIC & KINEMATIC ENGINE
-- =====================================================================

Core.updateTelemetry = function(currentNode, totalNodes)
    totalNodes = totalNodes or 0
    local loopTargetStr = (Config.TargetLoops == 0) and "Inf" or tostring(Config.TargetLoops)
    if currentNode and totalNodes > 0 then
        Core.UI.nodeStatsLabel.Text = string.format("Node: %d/%d | Loop: %d/%s", currentNode, totalNodes, Core.currentLoopCount, loopTargetStr)
        Core.UI.hudNodeLabel.Text = string.format("Node: %d/%d", currentNode, totalNodes)
        local progress = math.clamp(currentNode / totalNodes, 0, 1)
        TweenService:Create(Core.UI.progressBar, TweenInfo.new(0.1), { Size = UDim2.new(progress, 0, 1, 0) }):Play()
    else
        Core.UI.nodeStatsLabel.Text = string.format("Waypoints: %d | Loop: %d/%s", totalNodes, Core.currentLoopCount, loopTargetStr)
        Core.UI.hudNodeLabel.Text = string.format("Nodes: %d", totalNodes)
        Core.UI.progressBar.Size = UDim2.new(0, 0, 1, 0)
    end
    Core.UI.routeModeLabel.Text = string.format("%s (%.2fx)", Config.PlaybackMode, Config.SpeedMultiplier)
    Core.UI.hudLoopLabel.Text = string.format("Loop: %d/%s | %.1fx", Core.currentLoopCount, loopTargetStr, Config.SpeedMultiplier)
end

Core.getVisNode = function(idx)
    if Core.visualizerPool.Nodes[idx] then return Core.visualizerPool.Nodes[idx] end
    local sphere = Instance.new("SphereHandleAdornment")
    sphere.Adornee = visualizerAnchor; sphere.ZIndex = 1; sphere.AlwaysOnTop = false; sphere.Parent = visualizerFolder
    Core.visualizerPool.Nodes[idx] = sphere
    return sphere
end

Core.getVisBeam = function(idx)
    if Core.visualizerPool.Beams[idx] then return Core.visualizerPool.Beams[idx] end
    local line = Instance.new("LineHandleAdornment")
    line.Adornee = visualizerAnchor; line.Thickness = 4; line.ZIndex = 0; line.AlwaysOnTop = false; line.Parent = visualizerFolder
    Core.visualizerPool.Beams[idx] = line
    return line
end

Core.getVisLabel = function(idx)
    if Core.visualizerPool.Labels[idx] then return Core.visualizerPool.Labels[idx] end
    local attach = Instance.new("Attachment"); attach.Parent = visualizerAnchor
    local billboard = Instance.new("BillboardGui"); billboard.Adornee = attach; billboard.Size = UDim2.new(0, 48, 0, 18); billboard.StudsOffset = Vector3.new(0, 1.2, 0); billboard.AlwaysOnTop = true; billboard.Parent = visualizerFolder
    local tag = Instance.new("TextLabel"); tag.Size = UDim2.new(1, 0, 1, 0); tag.BackgroundTransparency = 1; tag.TextSize = 10; tag.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold); tag.Parent = billboard
    local lblData = { Billboard = billboard, Tag = tag, Attach = attach }
    Core.visualizerPool.Labels[idx] = lblData
    return lblData
end

Core.clearVisuals = function()
    Core.renderTicket = Core.renderTicket + 1
    for _, node in ipairs(Core.visualizerPool.Nodes) do node.Visible = false end
    for _, beam in ipairs(Core.visualizerPool.Beams) do beam.Visible = false end
    for _, lbl in ipairs(Core.visualizerPool.Labels) do lbl.Billboard.Enabled = false end
    activeNodeHalo.Transparency = 1
end

Core.setHaloTarget = function(pos)
    if not Config.VisualizerEnabled or not pos then
        activeNodeHalo.Transparency = 1; return
    end
    activeNodeHalo.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    activeNodeHalo.Transparency = 0.3
end

Core.renderVisualPath = function(waypointsList)
    Core.renderTicket = Core.renderTicket + 1
    local myTicket = Core.renderTicket

    task.spawn(function()
        for _, node in ipairs(Core.visualizerPool.Nodes) do node.Visible = false end
        for _, beam in ipairs(Core.visualizerPool.Beams) do beam.Visible = false end
        for _, lbl in ipairs(Core.visualizerPool.Labels) do lbl.Billboard.Enabled = false end
        
        if not Config.VisualizerEnabled or #waypointsList == 0 then return end

        local prevPos = nil
        for i, data in ipairs(waypointsList) do
            if Core.renderTicket ~= myTicket then return end
            if i % 150 == 0 then RunService.RenderStepped:Wait() end
            if Core.renderTicket ~= myTicket then return end

            local node = Core.getVisNode(i)
            node.CFrame = CFrame.new(data.pos)
            node.Radius = (i == 1 or i == #waypointsList) and 0.55 or 0.35
            node.Transparency = Config.VisualizerOpacity
            node.Visible = true

            if i == 1 then node.Color3 = Color3.fromRGB(0, 255, 128)
            elseif i == #waypointsList then node.Color3 = Color3.fromRGB(255, 60, 60)
            elseif data.isMouseClick then node.Color3 = Color3.fromRGB(255, 0, 80)
            elseif data.action or data.actionPromptName or data.isInteractionNode then node.Color3 = Color3.fromRGB(0, 170, 255)
            elseif data.pauseDuration and data.pauseDuration > 0.5 then node.Color3 = Color3.fromRGB(255, 215, 0)
            elseif data.jump then node.Color3 = Color3.fromRGB(255, 170, 0)
            elseif data.isSprinting then node.Color3 = Color3.fromRGB(255, 80, 180)
            else node.Color3 = Color3.fromRGB(50, 220, 120) end

            if Config.WaypointLabelsEnabled then
                local lblObj = Core.getVisLabel(i)
                lblObj.Attach.WorldPosition = data.pos
                lblObj.Billboard.Enabled = true
                
                if i == 1 then lblObj.Tag.Text = "[START]"; lblObj.Tag.TextColor3 = Color3.fromRGB(0, 255, 128)
                elseif i == #waypointsList then lblObj.Tag.Text = "[END]"; lblObj.Tag.TextColor3 = Color3.fromRGB(255, 80, 80)
                elseif data.isMouseClick then lblObj.Tag.Text = string.format("[MB1 %.1fs]", data.clickDuration or 0); lblObj.Tag.TextColor3 = Color3.fromRGB(255, 0, 80)
                elseif data.action or data.actionPromptName or data.isInteractionNode then lblObj.Tag.Text = string.format("[E %.1fs]", data.actionHoldDuration or 0); lblObj.Tag.TextColor3 = Color3.fromRGB(0, 200, 255)
                elseif data.pauseDuration and data.pauseDuration > 0.5 then lblObj.Tag.Text = string.format("[%.1fs]", data.pauseDuration); lblObj.Tag.TextColor3 = Color3.fromRGB(255, 215, 0)
                else lblObj.Tag.Text = tostring(i); lblObj.Tag.TextColor3 = Color3.fromRGB(255, 255, 255) end
            end

            if prevPos then
                local beam = Core.getVisBeam(i)
                beam.CFrame = CFrame.lookAt(prevPos, data.pos)
                beam.Length = (data.pos - prevPos).Magnitude
                beam.Color3 = Color3.fromRGB(120, 120, 140)
                beam.Transparency = math.clamp(Config.VisualizerOpacity + 0.3, 0, 0.9)
                beam.Visible = true
            end
            prevPos = data.pos
        end
    end)
end

Core.hookDeathFailSafe = function()
    if Core.scriptConnections.death then Core.scriptConnections.death:Disconnect(); Core.scriptConnections.death = nil end
    local char, _, hum = Core.getCharacter()
    if hum then
        Core.scriptConnections.death = hum.Died:Connect(function()
            if (Core.isRecording or Core.isPlaying) and Config.EmergencyLeaveOnDeath then game:Shutdown() end
        end)
    end
end
player.CharacterAdded:Connect(function() task.wait(0.5); Core.hookDeathFailSafe() end)
Core.hookDeathFailSafe()

Core.hookInputListeners = function()
    if Core.scriptConnections.jump then Core.scriptConnections.jump:Disconnect(); Core.scriptConnections.jump = nil end
    if Core.scriptConnections.state then Core.scriptConnections.state:Disconnect(); Core.scriptConnections.state = nil end
    if Core.scriptConnections.key then Core.scriptConnections.key:Disconnect(); Core.scriptConnections.key = nil end
    if Core.scriptConnections.keyEnd then Core.scriptConnections.keyEnd:Disconnect(); Core.scriptConnections.keyEnd = nil end

    Core.scriptConnections.jump = UserInputService.JumpRequest:Connect(function()
        if Core.isRecording then Core.jumpTriggered = true end
    end)

    Core.scriptConnections.key = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if Core.isRecording then
            if input.KeyCode == Enum.KeyCode.E then
                Core.holdStartTick = tick()
            elseif Config.RecordMouseClicks and input.UserInputType == Enum.UserInputType.MouseButton1 then
                Core.mb1StartTick = tick()
            end
        end
    end)

    Core.scriptConnections.keyEnd = UserInputService.InputEnded:Connect(function(input)
        if Core.isRecording then
            if input.KeyCode == Enum.KeyCode.E and Core.holdStartTick then
                local rawDuration = tick() - Core.holdStartTick
                local finalDuration = math.max(rawDuration, 0.1)
                Core.holdStartTick = nil

                local pos = Core.getEntityPosition()
                if not pos then return end
                local now = tick()
                local _, _, h = Core.getCharacter()
                local cam = workspace.CurrentCamera
                local aimPos = pos + (cam and (cam.CFrame.LookVector * 3.5) or Vector3.zero)

                table.insert(Core.Waypoints, {
                    pos = pos, promptPos = aimPos, jump = false, pauseDuration = 0, speed = h and h.WalkSpeed or 16,
                    isSprinting = h and (h.WalkSpeed > 17) or false, isInteractionNode = true,
                    actionHoldDuration = math.floor((finalDuration + 0.1) * 100) / 100, interactionCount = 1,
                    interClickDelay = 0.2, delay = now - Core.lastWaypointTime
                })
                Core.lastWaypointTime = now
                Core.updateTelemetry(nil, #Core.Waypoints)
                if Config.RealtimeVisualizer then Core.renderVisualPath(Core.Waypoints) end
                Core.showToast(string.format("Interaction Stamped (%.1fs)", finalDuration))
                
            elseif Config.RecordMouseClicks and input.UserInputType == Enum.UserInputType.MouseButton1 and Core.mb1StartTick then
                local rawDuration = tick() - Core.mb1StartTick
                local finalDuration = math.max(rawDuration, 0.05)
                Core.mb1StartTick = nil
                
                local pos = Core.getEntityPosition()
                if not pos then return end
                local now = tick()
                local _, _, h = Core.getCharacter()
                
                table.insert(Core.Waypoints, {
                    pos = pos, isMouseClick = true, clickDuration = math.floor((finalDuration) * 100) / 100,
                    jump = false, pauseDuration = 0, speed = h and h.WalkSpeed or 16, delay = now - Core.lastWaypointTime
                })
                Core.lastWaypointTime = now
                Core.updateTelemetry(nil, #Core.Waypoints)
                if Config.RealtimeVisualizer then Core.renderVisualPath(Core.Waypoints) end
                Core.showToast(string.format("Mouse Click Stamped (%.2fs)", finalDuration))
            end
        end
    end)

    local _, _, hum = Core.getCharacter()
    if hum then
        Core.scriptConnections.state = hum.StateChanged:Connect(function(oldState, newState)
            if Core.isRecording and newState == Enum.HumanoidStateType.Jumping then Core.jumpTriggered = true end
        end)
    end
end

Core.stopRecording = function()
    Core.isRecording = false
    Core.jumpTriggered = false
    Core.holdStartTick = nil
    Core.mb1StartTick = nil
    if Core.scriptConnections.jump then Core.scriptConnections.jump:Disconnect(); Core.scriptConnections.jump = nil end
    if Core.scriptConnections.key then Core.scriptConnections.key:Disconnect(); Core.scriptConnections.key = nil end
    if Core.scriptConnections.keyEnd then Core.scriptConnections.keyEnd:Disconnect(); Core.scriptConnections.keyEnd = nil end
    if Core.scriptConnections.state then Core.scriptConnections.state:Disconnect(); Core.scriptConnections.state = nil end
    if Core.UI.recordToggleControl and typeof(Core.UI.recordToggleControl.Get) == "function" and Core.UI.recordToggleControl.Get() then
        Core.UI.recordToggleControl.Set(false, true)
    end
    Core.updateStateBadge("IDLE", Color3.fromRGB(60, 65, 80))
    Core.renderVisualPath(Core.Waypoints)
    Core.updateTelemetry(nil, #Core.Waypoints)
    Core.playSoundFeedback(0.9)
    Core.showToast(string.format("Recording stopped (%d nodes)", #Core.Waypoints))
end

Core.startRecording = function()
    if Core.isRecording then return end
    if Core.isPlaying then
        if Core.UI.playToggleControl and typeof(Core.UI.playToggleControl.Set) == "function" then Core.UI.playToggleControl.Set(false, false) end
    end

    local initialPos = nil
    for _ = 1, 100 do
        initialPos = Core.getEntityPosition()
        if initialPos then break end
        task.wait(0.1)
    end

    if not initialPos then
        Core.triggerErrorModal("ERR_NO_PHYSICAL_ROOT", "Could not locate a valid physical root part on your character model.")
        if Core.UI.recordToggleControl and typeof(Core.UI.recordToggleControl.Set) == "function" then Core.UI.recordToggleControl.Set(false, true) end
        return
    end

    Core.Waypoints = {}
    Core.clearVisuals()
    Core.isRecording = true
    Core.jumpTriggered = false
    Core.holdStartTick = nil
    Core.mb1StartTick = nil
    Core.currentLoopCount = 0
    Core.lastWaypointTime = tick()
    Core.updateStateBadge("REC", activeTheme.RecordActive)
    Core.playSoundFeedback(1.2)
    Core.showToast("Recording started...")

    Core.hookInputListeners()
    local _, _, hum = Core.getCharacter()

    table.insert(Core.Waypoints, { pos = initialPos, jump = false, pauseDuration = 0, speed = hum and hum.WalkSpeed or 16, delay = 0.08 })
    Core.updateTelemetry(nil, #Core.Waypoints)
    if Config.RealtimeVisualizer then Core.renderVisualPath(Core.Waypoints) end

    task.spawn(function()
        local lastRecordedPos = initialPos
        local standingStillTime = 0

        while Core.isRecording do
            local pos = Core.getEntityPosition()
            if pos then
                local _, _, h = Core.getCharacter()
                local distMoved = (pos - lastRecordedPos).Magnitude
                local now = tick()
                local stampedJump = Core.jumpTriggered
                Core.jumpTriggered = false

                if distMoved > 0.4 or stampedJump then
                    standingStillTime = 0
                    table.insert(Core.Waypoints, {
                        pos = pos, jump = stampedJump, pauseDuration = 0,
                        speed = h and h.WalkSpeed or 16, isSprinting = h and (h.WalkSpeed > 17) or false,
                        delay = now - Core.lastWaypointTime
                    })
                    lastRecordedPos = pos
                    Core.lastWaypointTime = now
                    Core.updateTelemetry(nil, #Core.Waypoints)
                    if Config.RealtimeVisualizer then Core.renderVisualPath(Core.Waypoints) end
                else
                    standingStillTime = standingStillTime + 0.08
                    if #Core.Waypoints > 0 and standingStillTime > 0.6 then
                        Core.Waypoints[#Core.Waypoints].pauseDuration = math.floor(standingStillTime * 10) / 10
                    end
                end
            end
            task.wait(0.08)
        end
    end)
end

Core.stopPlayback = function()
    Core.isPlaying = false
    Core.setHaloTarget(nil)
    local _, root, hum = Core.getCharacter()
    if hum and root then hum:MoveTo(root.Position) elseif root then root.AssemblyLinearVelocity = Vector3.zero end
    if Core.UI.playToggleControl and typeof(Core.UI.playToggleControl.Get) == "function" and Core.UI.playToggleControl.Get() then
        Core.UI.playToggleControl.Set(false, true)
    end
    Core.updateStateBadge("IDLE", Color3.fromRGB(60, 65, 80))
    Core.updateTelemetry(nil, #Core.Waypoints)
    Core.showToast("Playback stopped.")
end

Core.sendExternalMacroCommand = function(key, durationMs)
    if not (writefile and Config.UseExternalBridge) then return false end
    local now = tick()
    if (now - Core.lastBridgeWriteTick) < 0.05 then
        Core.bridgeQueue = { Key = key, Duration = durationMs }
        return true
    end
    Core.lastBridgeWriteTick = now
    local cmd = string.format("HOLD_%s:%d", string.upper(tostring(key)), durationMs)
    task.spawn(function() pcall(function() writefile(Config.BridgeFileName, cmd) end) end)
    return true
end

task.spawn(function()
    while true do
        task.wait(0.05)
        if Core.bridgeQueue then
            local q = Core.bridgeQueue
            Core.bridgeQueue = nil
            Core.lastBridgeWriteTick = tick()
            pcall(function() writefile(Config.BridgeFileName, string.format("HOLD_%s:%d", string.upper(tostring(q.Key)), q.Duration)) end)
        end
    end
end)

Core.resolveAndTriggerPrompt = function(data, root)
    local targetPosition = data.promptPos or data.pos
    local camera = workspace.CurrentCamera
    local _, _, hum = Core.getCharacter()

    if hum then hum:Move(Vector3.zero, false) end
    if root then root.AssemblyLinearVelocity = Vector3.zero end

    local baseHoldTimeMs = math.floor((data.actionHoldDuration or 0.2) * 1000)
    local bufferedHoldTimeMs = baseHoldTimeMs + 150 -- 150ms buffer for hardware bridge
    local bufferedHoldTimeSec = bufferedHoldTimeMs / 1000
    local totalTimes = math.max(data.interactionCount or 1, 1)

    for count = 1, totalTimes do
        if not Core.isPlaying then break end

        if root and targetPosition then root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)) end
        if camera and targetPosition then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition) end
        
        for _ = 1, 5 do RunService.RenderStepped:Wait() end

        print(string.format("📡 [ManniskaFarm] Dispatching HOLD_E:%d to Macro...", bufferedHoldTimeMs))
        Core.sendExternalMacroCommand("E", bufferedHoldTimeMs)

        if VirtualInputManager then pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) end

        local startTime = tick()
        while (tick() - startTime) < bufferedHoldTimeSec and Core.isPlaying do
            if camera and targetPosition then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition) end
            RunService.RenderStepped:Wait()
        end

        if VirtualInputManager then pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end) end

        if totalTimes > 1 and count < totalTimes then
            task.wait(math.max((data.interClickDelay or 0.2) / Config.SpeedMultiplier, 0.2))
        end
    end
end

Core.navigateToPoint = function(targetPosition, maxSpeed)
    local _, liveRoot, _ = Core.getCharacter()
    if not liveRoot then return false end

    local currentPos = liveRoot.Position
    local totalDelta = Vector3.new(targetPosition.X - currentPos.X, 0, targetPosition.Z - currentPos.Z)
    local totalDistance = totalDelta.Magnitude

    if totalDistance <= (2.4 * Config.SpeedMultiplier) then return true end

    local stepCount = math.max(math.ceil(totalDistance / 2.0), 1)
    local stepVector = (targetPosition - currentPos) / stepCount

    for stepIdx = 1, stepCount do
        if not Core.isPlaying then return false end
        local subTarget = currentPos + (stepVector * stepIdx)
        local subTimeout = 0

        while Core.isPlaying do
            local _, curR, curH = Core.getCharacter()
            if not curR then return false end

            local cPos = curR.Position
            local flatDelta = Vector3.new(subTarget.X - cPos.X, 0, subTarget.Z - cPos.Z)
            local flatDist = flatDelta.Magnitude

            if flatDist <= (2.2 * Config.SpeedMultiplier) then break end

            local moveDir = flatDelta.Unit
            local s = (curH and curH.WalkSpeed > 0 and curH.WalkSpeed) or (maxSpeed or 16)

            if curH then
                curH:MoveTo(subTarget)
            else
                curR.AssemblyLinearVelocity = Vector3.new(moveDir.X * s, curR.AssemblyLinearVelocity.Y, moveDir.Z * s)
                curR.CFrame = CFrame.lookAt(curR.Position, Vector3.new(subTarget.X, curR.Position.Y, subTarget.Z))
            end

            subTimeout = subTimeout + 0.03
            if subTimeout > (2.5 / Config.SpeedMultiplier) then break end
            task.wait(0.03)
        end
    end
    return true
end

Core.checkPlayerProximityRadar = function(root)
    if not Config.ProximityRadar or not root then return false end
    local rootPos = root.Position
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local otherRoot = otherPlayer.Character.PrimaryPart or otherPlayer.Character:FindFirstChild("HumanoidRootPart") or otherPlayer.Character:FindFirstChildWhichIsA("BasePart")
            if otherRoot then
                local dist = (otherRoot.Position - rootPos).Magnitude
                if dist <= Config.RadarRadius then
                    if Config.RadarAction == "ServerHop" then
                        Core.showToast("Radar Alert: Player detected! Server hopping...")
                        task.spawn(function() TeleportService:Teleport(game.PlaceId, player) end)
                        return true
                    else
                        Core.showToast("Radar Alert: Player nearby. Pausing...")
                        return true
                    end
                end
            end
        end
    end
    return false
end

Core.startPlayback = function()
    if Core.isPlaying or #Core.Waypoints == 0 then return end
    if Core.isRecording then
        if Core.UI.recordToggleControl and typeof(Core.UI.recordToggleControl.Get) == "function" then Core.UI.recordToggleControl.Set(false, false) end
    end

    local _, root, _ = Core.getCharacter()
    if not root then
        Core.triggerErrorModal("ERR_PLAYBACK_STALL", "Cannot start playback: No character root part found.")
        if Core.UI.playToggleControl and typeof(Core.UI.playToggleControl.Set) == "function" then Core.UI.playToggleControl.Set(false, true) end
        return
    end

    Core.isPlaying = true
    Core.currentLoopCount = 0
    Core.updateStateBadge("PLAY", activeTheme.PlayActive)
    Core.playSoundFeedback(1.2)
    Core.showToast("Playback started: " .. Config.PlaybackMode)

    task.spawn(function()
        local directionForward = (Config.PlaybackMode ~= "Reverse")

        while Core.isPlaying do
            local _, curRoot, hum = Core.getCharacter()
            if not curRoot then break end

            local startIndex = directionForward and 1 or #Core.Waypoints
            local endIndex = directionForward and #Core.Waypoints or 1
            local step = directionForward and 1 or -1

            local initialNode = Core.Waypoints[startIndex]
            if initialNode then
                local startDist = (Vector3.new(initialNode.pos.X, 0, initialNode.pos.Z) - Vector3.new(curRoot.Position.X, 0, curRoot.Position.Z)).Magnitude
                if startDist > 3.0 then Core.navigateToPoint(initialNode.pos, 16 * Config.SpeedMultiplier) end
            end

            local i = startIndex
            while (directionForward and i <= endIndex) or (not directionForward and i >= endIndex) do
                if not Core.isPlaying then break end
                local data = Core.Waypoints[i]
                if not data then break end

                Core.updateTelemetry(i, #Core.Waypoints)
                Core.setHaloTarget(data.pos)

                if Core.checkPlayerProximityRadar(curRoot) and Config.RadarAction == "Pause" then
                    repeat task.wait(1) until not Core.checkPlayerProximityRadar(curRoot) or not Core.isPlaying
                end

                local speedDrift = 1.0
                if Config.MicroRandomization then speedDrift = 1.0 + (math.random(-4, 4) / 100) end
                local activeSpeed = (data.speed and data.speed > 0) and data.speed or 16
                
                if hum and Config.SpeedCurves then hum.WalkSpeed = activeSpeed * Config.SpeedMultiplier * speedDrift
                elseif hum then hum.WalkSpeed = 16 * Config.SpeedMultiplier * speedDrift end

                if Config.AutoTeleport and not data.isInteractionNode and not data.isMouseClick and not data.jump then
                    curRoot.CFrame = CFrame.new(data.pos)
                    task.wait(0.02 / Config.SpeedMultiplier)
                else
                    if data.isMouseClick then
                        if hum then hum:MoveTo(curRoot.Position) end
                        local holdTimeMs = math.max(math.floor((data.clickDuration or 0) * 1000), 50)
                        print(string.format("🖱️ [ManniskaFarm] Dispatching HOLD_MB1:%d to Macro...", holdTimeMs))
                        Core.sendExternalMacroCommand("MB1", holdTimeMs)
                        task.wait((data.clickDuration or 0) + 0.1)
                    end

                    if data.isInteractionNode or data.promptPos then
                        Core.resolveAndTriggerPrompt(data, curRoot)
                    end

                    if data.pauseDuration and data.pauseDuration > 0.3 and not data.isInteractionNode and not data.isMouseClick then
                        local pauseStart = tick()
                        local totalPause = data.pauseDuration / Config.SpeedMultiplier
                        while (tick() - pauseStart) < totalPause and Core.isPlaying do
                            local _, stillRoot, stillHum = Core.getCharacter()
                            if stillHum then stillHum:Move(Vector3.zero, false) end
                            if stillRoot then
                                stillRoot.AssemblyLinearVelocity = Vector3.zero
                                stillRoot.CFrame = CFrame.new(data.pos.X, stillRoot.Position.Y, data.pos.Z)
                            end
                            task.wait(0.05)
                        end
                    end

                    if data.jump then
                        if Config.MicroRandomization then task.wait(math.random(15, 55) / 1000) end
                        if hum and hum.FloorMaterial ~= Enum.Material.Air then
                            hum.Jump = true; hum:ChangeState(Enum.HumanoidStateType.Jumping)
                        else
                            local jumpPower = (hum and hum.JumpPower > 0) and hum.JumpPower or 50
                            curRoot.AssemblyLinearVelocity = Vector3.new(curRoot.AssemblyLinearVelocity.X, jumpPower, curRoot.AssemblyLinearVelocity.Z)
                        end
                    end

                    local targetPos = data.pos
                    if Config.MicroRandomization and not data.isInteractionNode and not data.jump and not data.isMouseClick then
                        targetPos = targetPos + Vector3.new((math.random(-20, 20) / 100), 0, (math.random(-20, 20) / 100))
                    end

                    local timeout = 0
                    local stuckClock = 0
                    local checkPos = Core.getEntityPosition() or curRoot.Position

                    while Core.isPlaying do
                        local _, dynamicRoot, dynamicHum = Core.getCharacter()
                        if not dynamicRoot then break end

                        local curPos = dynamicRoot.Position
                        local flatDelta = Vector3.new(targetPos.X - curPos.X, 0, targetPos.Z - curPos.Z)
                        local flatDist = flatDelta.Magnitude

                        if flatDist < (2.2 * Config.SpeedMultiplier) then break end

                        local moveDir = flatDelta.Unit
                        local s = (dynamicHum and dynamicHum.WalkSpeed > 0 and dynamicHum.WalkSpeed) or (activeSpeed * Config.SpeedMultiplier * speedDrift)

                        if dynamicHum then
                            dynamicHum:MoveTo(targetPos)
                            if dynamicHum.FloorMaterial == Enum.Material.Air and flatDist > 0.5 then
                                dynamicRoot.AssemblyLinearVelocity = Vector3.new(moveDir.X * s, dynamicRoot.AssemblyLinearVelocity.Y, moveDir.Z * s)
                            end
                        else
                            dynamicRoot.AssemblyLinearVelocity = Vector3.new(moveDir.X * s, dynamicRoot.AssemblyLinearVelocity.Y, moveDir.Z * s)
                            dynamicRoot.CFrame = CFrame.lookAt(dynamicRoot.Position, Vector3.new(targetPos.X, dynamicRoot.Position.Y, targetPos.Z))
                        end

                        if Config.FallDamper and dynamicRoot.AssemblyLinearVelocity.Y < -45 then
                            dynamicRoot.AssemblyLinearVelocity = Vector3.new(dynamicRoot.AssemblyLinearVelocity.X, -10, dynamicRoot.AssemblyLinearVelocity.Z)
                        end

                        if Config.AutoUnstuckEnabled or timeout > 1.2 then
                            stuckClock = stuckClock + 0.03
                            if stuckClock >= 0.5 then
                                local moved = (curPos - checkPos).Magnitude
                                if moved < 0.35 then
                                    if dynamicHum then dynamicHum.Jump = true; dynamicHum:ChangeState(Enum.HumanoidStateType.Jumping) end
                                    dynamicRoot.AssemblyLinearVelocity = Vector3.new(moveDir.X * (s + 6), 35, moveDir.Z * (s + 6))
                                end
                                checkPos = curPos
                                stuckClock = 0
                            end
                        end

                        timeout = timeout + 0.03
                        if timeout > (3.5 / Config.SpeedMultiplier) then break end
                        task.wait(0.03)
                    end
                end
                i = i + step
            end

            Core.currentLoopCount = Core.currentLoopCount + 1
            Core.updateTelemetry(nil, #Core.Waypoints)
            Core.playSoundFeedback(1.5)

            if Config.TargetLoops > 0 and Core.currentLoopCount >= Config.TargetLoops then
                Core.showToast(string.format("Completed %d loop(s). Stopping.", Config.TargetLoops))
                break
            end

            if Config.PlaybackMode == "One-Shot" or Config.PlaybackMode == "Reverse" then break
            elseif Config.PlaybackMode == "Ping-Pong" then directionForward = not directionForward end
        end
        Core.stopPlayback()
    end)
end

Core.undoLastNode = function()
    if #Core.Waypoints > 0 then
        table.remove(Core.Waypoints)
        Core.renderVisualPath(Core.Waypoints)
        Core.updateTelemetry(nil, #Core.Waypoints)
        Core.showToast(string.format("Undid node #%d", #Core.Waypoints + 1))
        Core.playSoundFeedback(0.8)
    else
        Core.showToast("No nodes to undo.")
    end
end

Core.clearWaypoints = function()
    Core.Waypoints = {}
    Core.clearVisuals()
    Core.currentLoopCount = 0
    Core.updateTelemetry(nil, 0)
    Core.showToast("Route waypoints cleared.")
end

Core.copyRouteToClipboard = function()
    if #Core.Waypoints == 0 then Core.showToast("No route data to export."); return end
    local exportTable = {}
    for _, wp in ipairs(Core.Waypoints) do
        table.insert(exportTable, {
            pos = { wp.pos.X, wp.pos.Y, wp.pos.Z },
            promptPos = wp.promptPos and { wp.promptPos.X, wp.promptPos.Y, wp.promptPos.Z } or nil,
            jump = wp.jump, pauseDuration = wp.pauseDuration or 0,
            speed = wp.speed or 16, isSprinting = wp.isSprinting or false, delay = wp.delay or 0.08,
            isInteractionNode = wp.isInteractionNode or false, interactionCount = wp.interactionCount or 1,
            interClickDelay = wp.interClickDelay or 0.15, actionHoldDuration = wp.actionHoldDuration or 0,
            isMouseClick = wp.isMouseClick or false, clickDuration = wp.clickDuration or 0
        })
    end
    local jsonString = HttpService:JSONEncode(exportTable)
    if setclipboard then setclipboard(jsonString); Core.showToast("Route JSON copied to clipboard!")
    else Core.showToast("Clipboard API unavailable.") end
end

Core.saveRouteToFile = function(fileName)
    local name = (fileName and fileName ~= "") and fileName or Config.FileName
    if not (writefile and isfile) then Core.triggerErrorModal("ERR_STORAGE_WRITE", "Your executor does not support the 'writefile' API."); return end
    local exportTable = {}
    for _, wp in ipairs(Core.Waypoints) do
        table.insert(exportTable, {
            pos = { wp.pos.X, wp.pos.Y, wp.pos.Z },
            promptPos = wp.promptPos and { wp.promptPos.X, wp.promptPos.Y, wp.promptPos.Z } or nil,
            jump = wp.jump, pauseDuration = wp.pauseDuration or 0,
            speed = wp.speed or 16, isSprinting = wp.isSSprint or false, delay = wp.delay or 0.08,
            isInteractionNode = wp.isInteractionNode or false, interactionCount = wp.interactionCount or 1,
            interClickDelay = wp.interClickDelay or 0.15, actionHoldDuration = wp.actionHoldDuration or 0,
            isMouseClick = wp.isMouseClick or false, clickDuration = wp.clickDuration or 0
        })
    end
    writefile(name, HttpService:JSONEncode(exportTable))
    Core.showToast("Saved route to: " .. name)
end

Core.loadRouteFromFile = function(fileName)
    local name = (fileName and fileName ~= "") and fileName or Config.FileName
    if not (readfile and isfile and isfile(name)) then Core.triggerErrorModal("ERR_FILE_NOT_FOUND", "Could not locate file '" .. name .. "'"); return end
    local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(name)) end)
    if success and typeof(decoded) == "table" then
        Core.Waypoints = {}
        for _, rawWp in ipairs(decoded) do
            table.insert(Core.Waypoints, {
                pos = Vector3.new(rawWp.pos[1], rawWp.pos[2], rawWp.pos[3]),
                promptPos = rawWp.promptPos and Vector3.new(rawWp.promptPos[1], rawWp.promptPos[2], rawWp.promptPos[3]) or nil,
                jump = rawWp.jump, pauseDuration = rawWp.pauseDuration or 0,
                speed = rawWp.speed or 16, isSprinting = rawWp.isSprinting or false, delay = rawWp.delay,
                isInteractionNode = rawWp.isInteractionNode or false, interactionCount = rawWp.interactionCount or 1,
                interClickDelay = rawWp.interClickDelay or 0.15, actionHoldDuration = rawWp.actionHoldDuration or 0,
                isMouseClick = rawWp.isMouseClick or false, clickDuration = rawWp.clickDuration or 0
            })
        end
        Core.renderVisualPath(Core.Waypoints); Core.currentLoopCount = 0; Core.updateTelemetry(nil, #Core.Waypoints)
        Core.showToast(string.format("Loaded %d waypoints from %s", #Core.Waypoints, name))
    else Core.triggerErrorModal("ERR_JSON_PARSE", "Failed to deserialize route data. The JSON formatting may be corrupted.") end
end

Core.terminateProcess = function()
    Core.stopRecording(); Core.stopPlayback(); Core.clearVisuals()
    for _, conn in ipairs(Core.scriptConnections) do
        if conn and typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    table.clear(Core.scriptConnections)
    if visualizerFolder then visualizerFolder:Destroy() end
    if visualizerAnchor then visualizerAnchor:Destroy() end
    _G.Autofarm_Control = nil
    if screenGui then screenGui:Destroy() end
end

-- Auto-Execute on Rejoin
task.spawn(function()
    if not (readfile and isfile and isfile("ManniskaFarm_AutoRun.json")) then return end
    local success, dec = pcall(function() return HttpService:JSONDecode(readfile("ManniskaFarm_AutoRun.json")) end)
    if success and typeof(dec) == "table" and dec.Enabled and dec.Route then
        if not game:IsLoaded() then game.Loaded:Wait() end
        local char = player.Character or player.CharacterAdded:Wait()
        task.wait(1.5)
        local _, root = Core.getCharacter()
        if root and root:IsA("BasePart") then
            task.wait(3.5)
            Core.loadRouteFromFile(dec.Route)
            task.wait(1.0)
            if Core.UI.playToggleControl and typeof(Core.UI.playToggleControl.Set) == "function" then Core.UI.playToggleControl.Set(true, false) else Core.startPlayback() end
            Core.showToast("Auto-Rejoin: Resumed route " .. dec.Route)
        end
    end
end)

_G.Autofarm_Control = {
    ToggleRecord = function(state) if state then Core.startRecording() else Core.stopRecording() end end,
    TogglePlay = function(state) if state then Core.startPlayback() else Core.stopPlayback() end end,
    Clear = Core.clearWaypoints, Undo = Core.undoLastNode, GetCount = function() return #Core.Waypoints end, GetLoops = function() return Core.currentLoopCount end,
    Save = Core.saveRouteToFile, Load = Core.loadRouteFromFile, Export = Core.copyRouteToClipboard, Terminate = Core.terminateProcess, Config = Config, Keybinds = Keybinds
}

print("🚀 Autofarm V14.0 (Master Engine Override) Loaded.")
