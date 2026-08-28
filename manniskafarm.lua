-- =====================================================================
--  MANNISKAFARM V13.1 - KINEMATIC FARMING & MACRO BRIDGE SUITE
-- =====================================================================

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

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

local scriptConnections = {}
local recordToggleControl = nil
local playToggleControl = nil
local activeToggles = {}

local function playSoundFeedback(pitch)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxasset://sounds/button.wav"
        sound.Volume = 0.4; sound.PlaybackSpeed = pitch or 1.0
        sound.Parent = workspace; sound:Play()
        task.delay(1, function() if sound and sound.Parent then sound:Destroy() end end)
    end)
end

local function setupAntiAFK()
    local idledConn = player.Idled:Connect(function()
        if Config.AntiAFKEnabled then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end)
    table.insert(scriptConnections, idledConn)
end
setupAntiAFK()

local function getCharacter()
    local char = player.Character
    local camera = workspace.CurrentCamera
    if not char or not char.Parent then char = workspace:FindFirstChild(player.Name) end
    
    local hum, root = nil, nil
    if char and typeof(char) == "Instance" then
        hum = char:FindFirstChildWhichIsA("Humanoid", true)
        if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then root = char.PrimaryPart end
        if not root then root = char:FindFirstChild("HumanoidRootPart", true) end
    end
    return char, root, hum
end

local function getEntityPosition()
    local _, root, _ = getCharacter()
    if root and root:IsA("BasePart") then return root.Position end
    return nil
end

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

-- Shared UI Handles
local updateStateBadge, showToast, triggerErrorModal, updateTelemetry, renderVisualPath, clearVisuals, setHaloTarget
local errorModal, statusHUD, hudBadgeLabel, hudNodeLabel, hudLoopLabel, hudBadge, progressBar, nodeStatsLabel, routeModeLabel, mainFrame, bgGradient
local startRecording, stopRecording, startPlayback, stopPlayback, clearWaypoints, undoLastNode, saveRouteToFile, loadRouteFromFile, copyRouteToClipboard, terminateProcess

-- Visualizer Setup (Object Pooling)
local visualizerFolder = workspace:FindFirstChild("ManniskaPathVisualizer") or Instance.new("Folder")
visualizerFolder.Name = "ManniskaPathVisualizer"
visualizerFolder.Parent = workspace

local activeNodeHalo = Instance.new("Part")
activeNodeHalo.Name = "ActiveTargetHalo"
activeNodeHalo.Shape = Enum.PartType.Cylinder
activeNodeHalo.Size = Vector3.new(0.3, 3, 3)
activeNodeHalo.Anchored = true; activeNodeHalo.CanCollide = false
activeNodeHalo.Material = Enum.Material.Neon; activeNodeHalo.Color = Color3.fromRGB(255, 230, 0)
activeNodeHalo.Transparency = 1; activeNodeHalo.CastShadow = false
activeNodeHalo.Parent = visualizerFolder

local visualizerPool = { Nodes = {}, Beams = {}, Labels = {} }

clearVisuals = function()
    for _, node in ipairs(visualizerPool.Nodes) do node.CFrame = CFrame.new(0,-5000,0); node.Transparency = 1 end
    for _, beam in ipairs(visualizerPool.Beams) do beam.CFrame = CFrame.new(0,-5000,0); beam.Transparency = 1 end
    activeNodeHalo.Transparency = 1
end

setHaloTarget = function(pos)
    if not Config.VisualizerEnabled or not pos then
        activeNodeHalo.Transparency = 1; return
    end
    activeNodeHalo.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    activeNodeHalo.Transparency = 0.3
end

-- UI Construction 
do
    errorModal = Instance.new("Frame")
    errorModal.Name = "ErrorModal"
    errorModal.Size = UDim2.new(0, 360, 0, 140)
    errorModal.Position = UDim2.new(0.5, -180, 0.4, -70)
    errorModal.BackgroundColor3 = Color3.fromRGB(24, 14, 18)
    errorModal.BorderSizePixel = 0
    errorModal.ZIndex = 50
    errorModal.Visible = false
    errorModal.Parent = screenGui

    local errCorner = Instance.new("UICorner")
    errCorner.CornerRadius = UDim.new(0, 10)
    errCorner.Parent = errorModal

    local errStroke = Instance.new("UIStroke")
    errStroke.Thickness = 1.5
    errStroke.Color = Color3.fromRGB(240, 70, 70)
    errStroke.Transparency = 0.2
    errStroke.Parent = errorModal

    local errTitle = Instance.new("TextLabel")
    errTitle.Size = UDim2.new(1, -24, 0, 24)
    errTitle.Position = UDim2.new(0, 14, 0, 10)
    errTitle.BackgroundTransparency = 1
    errTitle.Text = "⚠ EXECUTION ERROR"
    errTitle.TextColor3 = Color3.fromRGB(255, 80, 80)
    errTitle.TextSize = 13
    errTitle.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    errTitle.TextXAlignment = Enum.TextXAlignment.Left
    errTitle.ZIndex = 51
    errTitle.Parent = errorModal

    local errCodeLabel = Instance.new("TextLabel")
    errCodeLabel.Size = UDim2.new(1, -24, 0, 16)
    errCodeLabel.Position = UDim2.new(0, 14, 0, 34)
    errCodeLabel.BackgroundTransparency = 1
    errCodeLabel.Text = "CODE: ERR_GENERIC"
    errCodeLabel.TextColor3 = Color3.fromRGB(180, 140, 150)
    errCodeLabel.TextSize = 10
    errCodeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    errCodeLabel.TextXAlignment = Enum.TextXAlignment.Left
    errCodeLabel.ZIndex = 51
    errCodeLabel.Parent = errorModal

    local errDesc = Instance.new("TextLabel")
    errDesc.Size = UDim2.new(1, -28, 0, 40)
    errDesc.Position = UDim2.new(0, 14, 0, 54)
    errDesc.BackgroundTransparency = 1
    errDesc.Text = "An unknown error occurred."
    errDesc.TextColor3 = Color3.fromRGB(240, 240, 245)
    errDesc.TextSize = 11
    errDesc.TextWrapped = true
    errDesc.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    errDesc.TextXAlignment = Enum.TextXAlignment.Left
    errDesc.ZIndex = 51
    errDesc.Parent = errorModal

    local errDismissBtn = Instance.new("TextButton")
    errDismissBtn.Size = UDim2.new(1, -28, 0, 26)
    errDismissBtn.Position = UDim2.new(0, 14, 1, -34)
    errDismissBtn.BackgroundColor3 = Color3.fromRGB(45, 20, 28)
    errDismissBtn.BorderSizePixel = 0
    errDismissBtn.Text = "Dismiss"
    errDismissBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    errDismissBtn.TextSize = 11
    errDismissBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    errDismissBtn.ZIndex = 51
    errDismissBtn.Parent = errorModal

    local errBtnCorner = Instance.new("UICorner")
    errBtnCorner.CornerRadius = UDim.new(0, 6)
    errBtnCorner.Parent = errDismissBtn

    errDismissBtn.MouseButton1Click:Connect(function()
        errorModal.Visible = false
    end)

    triggerErrorModal = function(errorCode, description)
        errCodeLabel.Text = "CODE: " .. tostring(errorCode)
        errDesc.Text = tostring(description)
        errorModal.Visible = true
        playSoundFeedback(0.7)
    end

    statusHUD = Instance.new("Frame")
    statusHUD.Name = "PersistentStatusHUD"
    statusHUD.Size = UDim2.new(0, 310, 0, 38)
    statusHUD.Position = UDim2.new(1, -322, 0, 12)
    statusHUD.BackgroundColor3 = activeTheme.Background
    statusHUD.BackgroundTransparency = 0.2
    statusHUD.BorderSizePixel = 0
    statusHUD.Visible = Config.StatusHUDEnabled
    statusHUD.Parent = screenGui
    registerElement("Background", statusHUD, "BackgroundColor3")

    local hudCorner = Instance.new("UICorner")
    hudCorner.CornerRadius = UDim.new(0, 8)
    hudCorner.Parent = statusHUD

    local hudStroke = Instance.new("UIStroke")
    hudStroke.Thickness = 1
    hudStroke.Color = activeTheme.Border
    hudStroke.Transparency = 0.3
    hudStroke.Parent = statusHUD
    registerElement("Border", hudStroke, "Color")

    hudBadge = Instance.new("Frame")
    hudBadge.Name = "StatusBadge"
    hudBadge.Size = UDim2.new(0, 48, 0, 20)
    hudBadge.Position = UDim2.new(0, 10, 0.5, -10)
    hudBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
    hudBadge.BorderSizePixel = 0
    hudBadge.Parent = statusHUD

    local hudBadgeCorner = Instance.new("UICorner")
    hudBadgeCorner.CornerRadius = UDim.new(0, 4)
    hudBadgeCorner.Parent = hudBadge

    hudBadgeLabel = Instance.new("TextLabel")
    hudBadgeLabel.Size = UDim2.new(1, 0, 1, 0)
    hudBadgeLabel.BackgroundTransparency = 1
    hudBadgeLabel.Text = "IDLE"
    hudBadgeLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    hudBadgeLabel.TextSize = 9
    hudBadgeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    hudBadgeLabel.Parent = hudBadge

    hudNodeLabel = Instance.new("TextLabel")
    hudNodeLabel.Size = UDim2.new(0, 110, 1, 0)
    hudNodeLabel.Position = UDim2.new(0, 66, 0, 0)
    hudNodeLabel.BackgroundTransparency = 1
    hudNodeLabel.Text = "Node: 0/0"
    hudNodeLabel.TextColor3 = activeTheme.TextPrimary
    hudNodeLabel.TextSize = 11
    hudNodeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    hudNodeLabel.TextXAlignment = Enum.TextXAlignment.Left
    hudNodeLabel.Parent = statusHUD
    registerElement("TextPrimary", hudNodeLabel, "TextColor3")

    hudLoopLabel = Instance.new("TextLabel")
    hudLoopLabel.Size = UDim2.new(0, 120, 1, 0)
    hudLoopLabel.Position = UDim2.new(1, -130, 0, 0)
    hudLoopLabel.BackgroundTransparency = 1
    hudLoopLabel.Text = "Loop: 0/Inf | 1.0x"
    hudLoopLabel.TextColor3 = activeTheme.Accent
    hudLoopLabel.TextSize = 11
    hudLoopLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    hudLoopLabel.TextXAlignment = Enum.TextXAlignment.Right
    hudLoopLabel.Parent = statusHUD
    registerElement("AccentText", hudLoopLabel, "TextColor3")

    local hudDragging = false
    local hudDragStart, hudStartPos

    statusHUD.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            hudDragging = true
            hudDragStart = input.Position
            hudStartPos = statusHUD.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    hudDragging = false
                end
            end)
        end
    end)

    local hudMoveConn = UserInputService.InputChanged:Connect(function(input)
        if hudDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - hudDragStart
            statusHUD.Position = UDim2.new(
                hudStartPos.X.Scale,
                hudStartPos.X.Offset + delta.X,
                hudStartPos.Y.Scale,
                hudStartPos.Y.Offset + delta.Y
            )
        end
    end)
    table.insert(scriptConnections, hudMoveConn)

    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainWindow"
    mainFrame.Size = UDim2.new(0, 440, 0, 520)
    mainFrame.Position = UDim2.new(0.5, -220, 0.32, -260)
    mainFrame.BackgroundColor3 = activeTheme.Background
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    registerElement("Background", mainFrame, "BackgroundColor3")

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 1.2
    mainStroke.Color = activeTheme.Border
    mainStroke.Transparency = 0.2
    mainStroke.Parent = mainFrame
    registerElement("Border", mainStroke, "Color")

    bgGradient = Instance.new("UIGradient")
    bgGradient.Rotation = 45
    bgGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, activeTheme.Background),
        ColorSequenceKeypoint.new(1, activeTheme.GradientColor or activeTheme.Background)
    })
    bgGradient.Enabled = (activeTheme.GradientEnabled == true)
    bgGradient.Parent = mainFrame

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = activeTheme.Surface
    header.BackgroundTransparency = 0.2
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    registerElement("Surface", header, "BackgroundColor3")

    local headerPadding = Instance.new("UIPadding")
    headerPadding.PaddingLeft = UDim.new(0, 14)
    headerPadding.PaddingRight = UDim.new(0, 10)
    headerPadding.Parent = header

    local titleGroup = Instance.new("Frame")
    titleGroup.Size = UDim2.new(1, -110, 1, 0)
    titleGroup.BackgroundTransparency = 1
    titleGroup.Parent = header

    local titleLayout = Instance.new("UIListLayout")
    titleLayout.FillDirection = Enum.FillDirection.Vertical
    titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    titleLayout.Padding = UDim.new(0, 2)
    titleLayout.Parent = titleGroup

    local titleTopRow = Instance.new("Frame")
    titleTopRow.Size = UDim2.new(1, 0, 0, 16)
    titleTopRow.BackgroundTransparency = 1
    titleTopRow.Parent = titleGroup

    local titleTopLayout = Instance.new("UIListLayout")
    titleTopLayout.FillDirection = Enum.FillDirection.Horizontal
    titleTopLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    titleTopLayout.Padding = UDim.new(0, 8)
    titleTopLayout.Parent = titleTopRow

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0, 145, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "MANNISKAFARM V13.1"
    titleLabel.TextColor3 = activeTheme.TextPrimary
    titleLabel.TextSize = 13
    titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleTopRow
    registerElement("TextPrimary", titleLabel, "TextColor3")

    local stateBadge = Instance.new("Frame")
    stateBadge.Name = "StateBadge"
    stateBadge.Size = UDim2.new(0, 56, 0, 16)
    stateBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
    stateBadge.BackgroundTransparency = 0.2
    stateBadge.BorderSizePixel = 0
    stateBadge.Parent = titleTopRow

    local stateBadgeCorner = Instance.new("UICorner")
    stateBadgeCorner.CornerRadius = UDim.new(0, 4)
    stateBadgeCorner.Parent = stateBadge

    local stateBadgeLabel = Instance.new("TextLabel")
    stateBadgeLabel.Size = UDim2.new(1, 0, 1, 0)
    stateBadgeLabel.BackgroundTransparency = 1
    stateBadgeLabel.Text = "IDLE"
    stateBadgeLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
    stateBadgeLabel.TextSize = 9
    stateBadgeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    stateBadgeLabel.Parent = stateBadge

    updateStateBadge = function(stateName, color)
        stateBadgeLabel.Text = stateName
        hudBadgeLabel.Text = stateName
        TweenService:Create(stateBadge, TWEEN_QUICK, { BackgroundColor3 = color }):Play()
        TweenService:Create(hudBadge, TWEEN_QUICK, { BackgroundColor3 = color }):Play()
    end

    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "SubTitle"
    subLabel.Size = UDim2.new(1, 0, 0, 12)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "HARDWARE BRIDGE & INTERACTION SUITE"
    subLabel.TextColor3 = activeTheme.Accent
    subLabel.TextSize = 10
    subLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.Parent = titleGroup
    registerElement("AccentText", subLabel, "TextColor3")

    local headerBtnGroup = Instance.new("Frame")
    headerBtnGroup.Size = UDim2.new(0, 64, 1, 0)
    headerBtnGroup.Position = UDim2.new(1, -64, 0, 0)
    headerBtnGroup.BackgroundTransparency = 1
    headerBtnGroup.Parent = header

    local hBtnLayout = Instance.new("UIListLayout")
    hBtnLayout.FillDirection = Enum.FillDirection.Horizontal
    hBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    hBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    hBtnLayout.Padding = UDim.new(0, 6)
    hBtnLayout.Parent = headerBtnGroup

    local isMinimized = false
    local unminimizedHeight = 520

    local minBtn = Instance.new("TextButton")
    minBtn.Name = "MinButton"
    minBtn.Size = UDim2.new(0, 28, 0, 28)
    minBtn.BackgroundColor3 = activeTheme.Surface
    minBtn.BackgroundTransparency = 0.6
    minBtn.BorderSizePixel = 0
    minBtn.AutoButtonColor = false
    minBtn.Text = "—"
    minBtn.TextColor3 = activeTheme.TextSecondary
    minBtn.TextSize = 13
    minBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    minBtn.Parent = headerBtnGroup
    registerElement("Surface", minBtn, "BackgroundColor3")
    registerElement("TextSecondary", minBtn, "TextColor3")

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minBtn

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.BackgroundColor3 = activeTheme.Surface
    closeBtn.BackgroundTransparency = 0.6
    closeBtn.BorderSizePixel = 0
    closeBtn.AutoButtonColor = false
    closeBtn.Text = "×"
    closeBtn.TextColor3 = activeTheme.TextSecondary
    closeBtn.TextSize = 20
    closeBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    closeBtn.Parent = headerBtnGroup
    registerElement("Surface", closeBtn, "BackgroundColor3")
    registerElement("TextSecondary", closeBtn, "TextColor3")

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn

    minBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            unminimizedHeight = mainFrame.AbsoluteSize.Y
            TweenService:Create(mainFrame, TWEEN_QUICK, { Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, 48) }):Play()
        else
            TweenService:Create(mainFrame, TWEEN_QUICK, { Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, unminimizedHeight) }):Play()
        end
    end)

    local isGuiOpen = true
    local function setGuiVisible(visible)
        isGuiOpen = visible
        if visible then
            mainFrame.Visible = true
            mainFrame.BackgroundTransparency = 1
            TweenService:Create(mainFrame, TWEEN_QUICK, { BackgroundTransparency = 0.15 }):Play()
        else
            local closeTween = TweenService:Create(mainFrame, TWEEN_QUICK, { BackgroundTransparency = 1 })
            closeTween:Play()
            closeTween.Completed:Connect(function()
                if not isGuiOpen then
                    mainFrame.Visible = false
                end
            end)
        end
    end

    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, TWEEN_QUICK, { BackgroundColor3 = Color3.fromRGB(235, 75, 75), BackgroundTransparency = 0, TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, TWEEN_QUICK, { BackgroundColor3 = activeTheme.Surface, BackgroundTransparency = 0.6, TextColor3 = activeTheme.TextSecondary }):Play()
    end)
    closeBtn.MouseButton1Click:Connect(function()
        setGuiVisible(false)
    end)

    local progressTrack = Instance.new("Frame")
    progressTrack.Name = "ProgressTrack"
    progressTrack.Size = UDim2.new(1, 0, 0, 2)
    progressTrack.Position = UDim2.new(0, 0, 0, 48)
    progressTrack.BackgroundColor3 = activeTheme.Border
    progressTrack.BorderSizePixel = 0
    progressTrack.Parent = mainFrame
    registerElement("Border", progressTrack, "BackgroundColor3")

    progressBar = Instance.new("Frame")
    progressBar.Name = "ProgressBar"
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = activeTheme.Accent
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressTrack
    registerElement("AccentBg", progressBar, "BackgroundColor3")

    local toastFrame = Instance.new("Frame")
    toastFrame.Name = "Toast"
    toastFrame.Size = UDim2.new(1, -28, 0, 32)
    toastFrame.Position = UDim2.new(0, 14, 1, 40)
    toastFrame.BackgroundColor3 = activeTheme.Surface
    toastFrame.BorderSizePixel = 0
    toastFrame.ZIndex = 20
    toastFrame.Parent = mainFrame
    registerElement("Surface", toastFrame, "BackgroundColor3")

    local toastCorner = Instance.new("UICorner")
    toastCorner.CornerRadius = UDim.new(0, 6)
    toastCorner.Parent = toastFrame

    local toastStroke = Instance.new("UIStroke")
    toastStroke.Thickness = 1
    toastStroke.Color = activeTheme.Accent
    toastStroke.Transparency = 0.4
    toastStroke.Parent = toastFrame
    registerElement("AccentBg", toastStroke, "Color")

    local toastLabel = Instance.new("TextLabel")
    toastLabel.Size = UDim2.new(1, -16, 1, 0)
    toastLabel.Position = UDim2.new(0, 8, 0, 0)
    toastLabel.BackgroundTransparency = 1
    toastLabel.Text = "Notification"
    toastLabel.TextColor3 = activeTheme.TextPrimary
    toastLabel.TextSize = 11
    toastLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    toastLabel.ZIndex = 21
    toastLabel.Parent = toastFrame
    registerElement("TextPrimary", toastLabel, "TextColor3")

    local toastSerial = 0
    showToast = function(message)
        toastLabel.Text = message
        toastSerial = toastSerial + 1
        local mySerial = toastSerial

        task.spawn(function()
            TweenService:Create(toastFrame, TWEEN_BOUNCE, { Position = UDim2.new(0, 14, 1, -44) }):Play()
            task.wait(2.2)
            if toastSerial == mySerial then
                TweenService:Create(toastFrame, TWEEN_QUICK, { Position = UDim2.new(0, 14, 1, 40) }):Play()
            end
        end)
    end

    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "Tabs"
    tabContainer.Size = UDim2.new(1, 0, 0, 36)
    tabContainer.Position = UDim2.new(0, 0, 0, 50)
    tabContainer.BackgroundColor3 = activeTheme.Surface
    tabContainer.BackgroundTransparency = 0.6
    tabContainer.BorderSizePixel = 0
    tabContainer.Parent = mainFrame
    registerElement("Surface", tabContainer, "BackgroundColor3")

    local tabPadding = Instance.new("UIPadding")
    tabPadding.PaddingLeft = UDim.new(0, 12)
    tabPadding.PaddingRight = UDim.new(0, 12)
    tabPadding.Parent = tabContainer

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.Parent = tabContainer

    local pages = {}
    local function createPage(name)
        local page = Instance.new("ScrollingFrame")
        page.Name = name .. "Page"
        page.Size = UDim2.new(1, 0, 1, -86)
        page.Position = UDim2.new(0, 0, 0, 86)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = activeTheme.Border
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = mainFrame
        registerElement("Border", page, "ScrollBarImageColor3")

        local pPadding = Instance.new("UIPadding")
        pPadding.PaddingTop = UDim.new(0, 10)
        pPadding.PaddingBottom = UDim.new(0, 16)
        pPadding.PaddingLeft = UDim.new(0, 14)
        pPadding.PaddingRight = UDim.new(0, 14)
        pPadding.Parent = page

        local pList = Instance.new("UIListLayout")
        pList.SortOrder = Enum.SortOrder.LayoutOrder
        pList.Padding = UDim.new(0, 8)
        pList.Parent = page

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
        tabBtn.Size = UDim2.new(0, 72, 1, 0)
        tabBtn.BackgroundTransparency = 1
        tabBtn.Text = name
        tabBtn.TextColor3 = isDefault and activeTheme.Accent or activeTheme.TextSecondary
        tabBtn.TextSize = 11
        tabBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
        tabBtn.Parent = tabContainer

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.new(1, 0, 0, 2)
        indicator.Position = UDim2.new(0, 0, 1, -2)
        indicator.BackgroundColor3 = activeTheme.Accent
        indicator.BackgroundTransparency = isDefault and 0 or 1
        indicator.BorderSizePixel = 0
        indicator.Parent = tabBtn
        registerElement("AccentBg", indicator, "BackgroundColor3")

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
        row.Name = name
        row.LayoutOrder = order
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = activeTheme.Surface
        row.BackgroundTransparency = 0.5
        row.BorderSizePixel = 0
        row.Parent = parent
        registerElement("Surface", row, "BackgroundColor3")

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row

        local rowStroke = Instance.new("UIStroke")
        rowStroke.Thickness = 1
        rowStroke.Color = activeTheme.Border
        rowStroke.Transparency = 0.5
        rowStroke.Parent = row
        registerElement("Border", rowStroke, "Color")

        local rowPadding = Instance.new("UIPadding")
        rowPadding.PaddingLeft = UDim.new(0, 14)
        rowPadding.PaddingRight = UDim.new(0, 14)
        rowPadding.Parent = row

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -60, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = activeTheme.TextPrimary
        label.TextSize = 12
        label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = row
        registerElement("TextPrimary", label, "TextColor3")

        local switchTrack = Instance.new("TextButton")
        switchTrack.Name = "Track"
        switchTrack.Size = UDim2.new(0, 42, 0, 22)
        switchTrack.Position = UDim2.new(1, -42, 0.5, -11)
        switchTrack.BackgroundColor3 = defaultState and activeColor or activeTheme.ToggleOff
        switchTrack.BackgroundTransparency = 0.2
        switchTrack.BorderSizePixel = 0
        switchTrack.AutoButtonColor = false
        switchTrack.Text = ""
        switchTrack.Parent = row

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = switchTrack

        local switchKnob = Instance.new("Frame")
        switchKnob.Name = "Knob"
        switchKnob.Size = UDim2.new(0, 16, 0, 16)
        switchKnob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        switchKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        switchKnob.BorderSizePixel = 0
        switchKnob.Parent = switchTrack

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = switchKnob

        local isToggled = defaultState or false
        local isInternalSetting = false

        local function setToggleState(state, suppressCallback)
            if isInternalSetting then return end
            isToggled = state
            local targetTrackColor = isToggled and activeColor or activeTheme.ToggleOff
            local targetKnobPos = isToggled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            local targetBorder = isToggled and activeColor or activeTheme.Border

            TweenService:Create(switchTrack, TWEEN_QUICK, { BackgroundColor3 = targetTrackColor }):Play()
            TweenService:Create(switchKnob, TWEEN_BOUNCE, { Position = targetKnobPos }):Play()
            TweenService:Create(rowStroke, TWEEN_QUICK, { Color = targetBorder }):Play()

            if not suppressCallback and typeof(onToggled) == "function" then
                isInternalSetting = true
                pcall(function() onToggled(isToggled) end)
                isInternalSetting = false
            end
        end

        table.insert(activeToggles, {
            UpdateTheme = function()
                if not isToggled then
                    switchTrack.BackgroundColor3 = activeTheme.ToggleOff
                    rowStroke.Color = activeTheme.Border
                end
            end
        })

        switchTrack.MouseButton1Click:Connect(function() setToggleState(not isToggled) end)
        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                setToggleState(not isToggled)
            end
        end)

        return { Set = setToggleState, Get = function() return isToggled end }
    end

    local function createActionButton(parent, labelText, order, onClick, customColor)
        local btn = Instance.new("TextButton")
        btn.Name = "ActionButton"
        btn.LayoutOrder = order
        btn.Size = UDim2.new(1, 0, 0, 36)
        btn.BackgroundColor3 = customColor or activeTheme.Surface
        btn.BackgroundTransparency = customColor and 0.25 or 0.4
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Text = labelText
        btn.TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary
        btn.TextSize = 12
        btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
        btn.Parent = parent
        if not customColor then
            registerElement("Surface", btn, "BackgroundColor3")
            registerElement("TextSecondary", btn, "TextColor3")
        end

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Thickness = 1
        btnStroke.Color = customColor or activeTheme.Border
        btnStroke.Transparency = 0.5
        btnStroke.Parent = btn
        if not customColor then
            registerElement("Border", btnStroke, "Color")
        end

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Border, TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
        end)

        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Surface, TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary }):Play()
        end)

        btn.MouseButton1Click:Connect(function()
            local flash = TweenService:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = activeTheme.Accent, TextColor3 = Color3.fromRGB(255, 255, 255) })
            flash:Play()
            flash.Completed:Connect(function()
                TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = customColor or activeTheme.Surface, TextColor3 = customColor and Color3.fromRGB(255, 255, 255) or activeTheme.TextSecondary }):Play()
            end)
            if typeof(onClick) == "function" then onClick() end
        end)

        return btn
    end

    local function createSliderRow(parent, name, labelText, minVal, maxVal, defaultVal, formatStr, onValueChanged, order)
        local row = Instance.new("Frame")
        row.Name = name
        row.LayoutOrder = order
        row.Size = UDim2.new(1, 0, 0, 48)
        row.BackgroundColor3 = activeTheme.Surface
        row.BackgroundTransparency = 0.5
        row.BorderSizePixel = 0
        row.Parent = parent
        registerElement("Surface", row, "BackgroundColor3")

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row

        local rowStroke = Instance.new("UIStroke")
        rowStroke.Thickness = 1
        rowStroke.Color = activeTheme.Border
        rowStroke.Transparency = 0.5
        rowStroke.Parent = row
        registerElement("Border", rowStroke, "Color")

        local rowPadding = Instance.new("UIPadding")
        rowPadding.PaddingLeft = UDim.new(0, 14)
        rowPadding.PaddingRight = UDim.new(0, 14)
        rowPadding.Parent = row

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(0.6, 0, 0, 20)
        titleLbl.Position = UDim2.new(0, 0, 0, 6)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = labelText
        titleLbl.TextColor3 = activeTheme.TextPrimary
        titleLbl.TextSize = 12
        titleLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = row
        registerElement("TextPrimary", titleLbl, "TextColor3")

        local valLbl = Instance.new("TextLabel")
        valLbl.Size = UDim2.new(0.4, 0, 0, 20)
        valLbl.Position = UDim2.new(0.6, 0, 0, 6)
        valLbl.BackgroundTransparency = 1
        valLbl.Text = (formatStr == "Loops: %d" and defaultVal == 0) and "Loops: Inf" or string.format(formatStr, defaultVal)
        valLbl.TextColor3 = activeTheme.Accent
        valLbl.TextSize = 12
        valLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        valLbl.TextXAlignment = Enum.TextXAlignment.Right
        valLbl.Parent = row
        registerElement("AccentText", valLbl, "TextColor3")

        local sliderBar = Instance.new("Frame")
        sliderBar.Name = "SliderTrack"
        sliderBar.Size = UDim2.new(1, 0, 0, 6)
        sliderBar.Position = UDim2.new(0, 0, 1, -14)
        sliderBar.BackgroundColor3 = activeTheme.ToggleOff
        sliderBar.BorderSizePixel = 0
        sliderBar.Parent = row
        registerElement("ToggleOff", sliderBar, "BackgroundColor3")

        local sCorner = Instance.new("UICorner")
        sCorner.CornerRadius = UDim.new(1, 0)
        sCorner.Parent = sliderBar

        local fillBar = Instance.new("Frame")
        local initRatio = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
        fillBar.Size = UDim2.new(initRatio, 0, 1, 0)
        fillBar.BackgroundColor3 = activeTheme.Accent
        fillBar.BorderSizePixel = 0
        fillBar.Parent = sliderBar
        registerElement("AccentBg", fillBar, "BackgroundColor3")

        local fCorner = Instance.new("UICorner")
        fCorner.CornerRadius = UDim.new(1, 0)
        fCorner.Parent = fillBar

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
            if typeof(onValueChanged) == "function" then
                onValueChanged(calcVal)
            end
        end

        sliderBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingSlider = true
                updateValue(input.Position.X)
            end
        end)

        local moveConn = UserInputService.InputChanged:Connect(function(input)
            if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                updateValue(input.Position.X)
            end
        end)
        table.insert(scriptConnections, moveConn)

        local endConn = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingSlider = false
            end
        end)
        table.insert(scriptConnections, endConn)

        return row
    end

    local function createSectionHeader(parent, titleText, order)
        local secHeader = Instance.new("TextLabel")
        secHeader.LayoutOrder = order
        secHeader.Size = UDim2.new(1, 0, 0, 20)
        secHeader.BackgroundTransparency = 1
        secHeader.Text = string.upper(titleText)
        secHeader.TextColor3 = activeTheme.Accent
        secHeader.TextSize = 10
        secHeader.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        secHeader.TextXAlignment = Enum.TextXAlignment.Left
        secHeader.Parent = parent
        registerElement("AccentText", secHeader, "TextColor3")
        return secHeader
    end

    local telemetryCard = Instance.new("Frame")
    telemetryCard.Name = "TelemetryCard"
    telemetryCard.LayoutOrder = 1
    telemetryCard.Size = UDim2.new(1, 0, 0, 44)
    telemetryCard.BackgroundColor3 = activeTheme.Surface
    telemetryCard.BackgroundTransparency = 0.35
    telemetryCard.BorderSizePixel = 0
    telemetryCard.Parent = controlsPage
    registerElement("Surface", telemetryCard, "BackgroundColor3")

    local tCardCorner = Instance.new("UICorner")
    tCardCorner.CornerRadius = UDim.new(0, 8)
    tCardCorner.Parent = telemetryCard

    local tCardStroke = Instance.new("UIStroke")
    tCardStroke.Thickness = 1
    tCardStroke.Color = activeTheme.Border
    tCardStroke.Transparency = 0.4
    tCardStroke.Parent = telemetryCard
    registerElement("Border", tCardStroke, "Color")

    local tCardPadding = Instance.new("UIPadding")
    tCardPadding.PaddingLeft = UDim.new(0, 14)
    tCardPadding.PaddingRight = UDim.new(0, 14)
    tCardPadding.Parent = telemetryCard

    nodeStatsLabel = Instance.new("TextLabel")
    nodeStatsLabel.Size = UDim2.new(0.58, -4, 1, 0)
    nodeStatsLabel.Position = UDim2.new(0, 0, 0, 0)
    nodeStatsLabel.BackgroundTransparency = 1
    nodeStatsLabel.Text = "Waypoints: 0 | Loop: 0/Inf"
    nodeStatsLabel.TextColor3 = activeTheme.TextPrimary
    nodeStatsLabel.TextSize = 11
    nodeStatsLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    nodeStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
    nodeStatsLabel.Parent = telemetryCard
    registerElement("TextPrimary", nodeStatsLabel, "TextColor3")

    routeModeLabel = Instance.new("TextLabel")
    routeModeLabel.Size = UDim2.new(0.42, -4, 1, 0)
    routeModeLabel.Position = UDim2.new(0.58, 4, 0, 0)
    routeModeLabel.BackgroundTransparency = 1
    routeModeLabel.Text = "Mode: Loop (1.00x)"
    routeModeLabel.TextColor3 = activeTheme.Accent
    routeModeLabel.TextSize = 11
    routeModeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    routeModeLabel.TextXAlignment = Enum.TextXAlignment.Right
    routeModeLabel.Parent = telemetryCard
    registerElement("AccentText", routeModeLabel, "TextColor3")

    recordToggleControl = createToggleRow(controlsPage, "RecordToggle", "Record Route Path", activeTheme.RecordActive, function(state)
        if state then startRecording() else stopRecording() end
    end, 2)

    playToggleControl = createToggleRow(controlsPage, "PlayToggle", "Execute Playback Route", activeTheme.PlayActive, function(state)
        if state then startPlayback() else stopPlayback() end
    end, 3)

    local fileRow = Instance.new("Frame")
    fileRow.Name = "FileRow"
    fileRow.LayoutOrder = 4
    fileRow.Size = UDim2.new(1, 0, 0, 42)
    fileRow.BackgroundColor3 = activeTheme.Surface
    fileRow.BackgroundTransparency = 0.5
    fileRow.BorderSizePixel = 0
    fileRow.Parent = controlsPage
    registerElement("Surface", fileRow, "BackgroundColor3")

    local fileCorner = Instance.new("UICorner")
    fileCorner.CornerRadius = UDim.new(0, 8)
    fileCorner.Parent = fileRow

    local fileStroke = Instance.new("UIStroke")
    fileStroke.Thickness = 1
    fileStroke.Color = activeTheme.Border
    fileStroke.Transparency = 0.5
    fileStroke.Parent = fileRow
    registerElement("Border", fileStroke, "Color")

    local fileInput = Instance.new("TextBox")
    fileInput.Size = UDim2.new(1, -156, 1, 0)
    fileInput.Position = UDim2.new(0, 10, 0, 0)
    fileInput.BackgroundTransparency = 1
    fileInput.Text = "ManniskaFarm_Route.json"
    fileInput.PlaceholderText = "RouteFileName.json"
    fileInput.TextColor3 = activeTheme.TextPrimary
    fileInput.TextSize = 12
    fileInput.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    fileInput.TextXAlignment = Enum.TextXAlignment.Left
    fileInput.ClearTextOnFocus = false
    fileInput.Parent = fileRow
    registerElement("TextPrimary", fileInput, "TextColor3")

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0, 64, 0, 26)
    saveBtn.Position = UDim2.new(1, -138, 0.5, -13)
    saveBtn.BackgroundColor3 = activeTheme.Border
    saveBtn.BackgroundTransparency = 0.3
    saveBtn.BorderSizePixel = 0
    saveBtn.Text = "Save"
    saveBtn.TextColor3 = activeTheme.TextPrimary
    saveBtn.TextSize = 11
    saveBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    saveBtn.Parent = fileRow

    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 6)
    saveCorner.Parent = saveBtn

    saveBtn.MouseButton1Click:Connect(function()
        saveRouteToFile(fileInput.Text)
    end)

    local loadBtn = Instance.new("TextButton")
    loadBtn.Size = UDim2.new(0, 64, 0, 26)
    loadBtn.Position = UDim2.new(1, -68, 0.5, -13)
    loadBtn.BackgroundColor3 = activeTheme.Accent
    loadBtn.BackgroundTransparency = 0.2
    loadBtn.BorderSizePixel = 0
    loadBtn.Text = "Load"
    loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    loadBtn.TextSize = 11
    loadBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    loadBtn.Parent = fileRow

    local loadCorner = Instance.new("UICorner")
    loadCorner.CornerRadius = UDim.new(0, 6)
    loadCorner.Parent = loadBtn

    loadBtn.MouseButton1Click:Connect(function()
        loadRouteFromFile(fileInput.Text)
    end)

    local dropdownCard = Instance.new("Frame")
    dropdownCard.Name = "DropdownCard"
    dropdownCard.LayoutOrder = 5
    dropdownCard.Size = UDim2.new(1, 0, 0, 72)
    dropdownCard.BackgroundColor3 = activeTheme.Surface
    dropdownCard.BackgroundTransparency = 0.6
    dropdownCard.BorderSizePixel = 0
    dropdownCard.Parent = controlsPage
    registerElement("Surface", dropdownCard, "BackgroundColor3")

    local ddCorner = Instance.new("UICorner")
    ddCorner.CornerRadius = UDim.new(0, 8)
    ddCorner.Parent = dropdownCard

    local ddStroke = Instance.new("UIStroke")
    ddStroke.Thickness = 1
    ddStroke.Color = activeTheme.Border
    ddStroke.Transparency = 0.5
    ddStroke.Parent = dropdownCard
    registerElement("Border", ddStroke, "Color")

    local ddList = Instance.new("ScrollingFrame")
    ddList.Size = UDim2.new(1, -12, 1, -8)
    ddList.Position = UDim2.new(0, 6, 0, 4)
    ddList.BackgroundTransparency = 1
    ddList.BorderSizePixel = 0
    ddList.ScrollBarThickness = 2
    ddList.ScrollBarImageColor3 = activeTheme.Accent
    ddList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ddList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ddList.Parent = dropdownCard
    registerElement("AccentBg", ddList, "ScrollBarImageColor3")

    local ddLayout = Instance.new("UIListLayout")
    ddLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ddLayout.Padding = UDim.new(0, 4)
    ddLayout.Parent = ddList

    local function refreshFileList()
        for _, child in ipairs(ddList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        local files = (listfiles and typeof(listfiles) == "function") and listfiles("") or { "ManniskaFarm_Route.json" }
        for _, path in ipairs(files) do
            if string.find(path, ".json") then
                local cleanName = string.gsub(path, "^.*[\\/]", "")
                local fBtn = Instance.new("TextButton")
                fBtn.Size = UDim2.new(1, 0, 0, 22)
                fBtn.BackgroundColor3 = activeTheme.ToggleOff
                fBtn.BackgroundTransparency = 0.4
                fBtn.BorderSizePixel = 0
                fBtn.Text = "   📁 " .. cleanName
                fBtn.TextColor3 = activeTheme.TextPrimary
                fBtn.TextSize = 10
                fBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
                fBtn.TextXAlignment = Enum.TextXAlignment.Left
                fBtn.Parent = ddList

                local fCorner = Instance.new("UICorner")
                fCorner.CornerRadius = UDim.new(0, 4)
                fCorner.Parent = fBtn

                fBtn.MouseButton1Click:Connect(function()
                    fileInput.Text = cleanName
                    loadRouteFromFile(cleanName)
                end)
            end
        end
    end
    refreshFileList()

    createActionButton(controlsPage, "Undo Last Node (Z)", 6, function() undoLastNode() end)
    createActionButton(controlsPage, "Copy JSON to Clipboard", 7, function() copyRouteToClipboard() end)
    createActionButton(controlsPage, "Clear Path Waypoints", 8, function() clearWaypoints() end)

    createSectionHeader(settingsPage, "Playback & Scaling", 1)

    local modeRow = Instance.new("Frame")
    modeRow.Name = "ModeSetting"
    modeRow.LayoutOrder = 2
    modeRow.Size = UDim2.new(1, 0, 0, 42)
    modeRow.BackgroundColor3 = activeTheme.Surface
    modeRow.BackgroundTransparency = 0.5
    modeRow.BorderSizePixel = 0
    modeRow.Parent = settingsPage
    registerElement("Surface", modeRow, "BackgroundColor3")

    local modeCorner = Instance.new("UICorner")
    modeCorner.CornerRadius = UDim.new(0, 8)
    modeCorner.Parent = modeRow

    local modeStroke = Instance.new("UIStroke")
    modeStroke.Thickness = 1
    modeStroke.Color = activeTheme.Border
    modeStroke.Transparency = 0.5
    modeStroke.Parent = modeRow
    registerElement("Border", modeStroke, "Color")

    local modePadding = Instance.new("UIPadding")
    modePadding.PaddingLeft = UDim.new(0, 14)
    modePadding.PaddingRight = UDim.new(0, 14)
    modePadding.Parent = modeRow

    local modeLabel = Instance.new("TextLabel")
    modeLabel.Size = UDim2.new(1, -120, 1, 0)
    modeLabel.BackgroundTransparency = 1
    modeLabel.Text = "Playback Route Mode"
    modeLabel.TextColor3 = activeTheme.TextPrimary
    modeLabel.TextSize = 12
    modeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    modeLabel.TextXAlignment = Enum.TextXAlignment.Left
    modeLabel.Parent = modeRow
    registerElement("TextPrimary", modeLabel, "TextColor3")

    local modeBtn = Instance.new("TextButton")
    modeBtn.Size = UDim2.new(0, 100, 0, 26)
    modeBtn.Position = UDim2.new(1, -100, 0.5, -13)
    modeBtn.BackgroundColor3 = activeTheme.ToggleOff
    modeBtn.BackgroundTransparency = 0.2
    modeBtn.BorderSizePixel = 0
    modeBtn.Text = Config.PlaybackMode
    modeBtn.TextColor3 = activeTheme.Accent
    modeBtn.TextSize = 11
    modeBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    modeBtn.Parent = modeRow
    registerElement("ToggleOff", modeBtn, "BackgroundColor3")

    local modeBtnCorner = Instance.new("UICorner")
    modeBtnCorner.CornerRadius = UDim.new(0, 6)
    modeBtnCorner.Parent = modeBtn

    local modes = { "Loop", "Ping-Pong", "One-Shot", "Reverse" }
    local modeIdx = 1
    modeBtn.MouseButton1Click:Connect(function()
        modeIdx = (modeIdx % #modes) + 1
        Config.PlaybackMode = modes[modeIdx]
        modeBtn.Text = Config.PlaybackMode
        updateTelemetry(nil, #Waypoints)
    end)

    createSliderRow(settingsPage, "LoopSlider", "Loop Count Limit", 0, 200, Config.TargetLoops, "Loops: %d", function(val)
        Config.TargetLoops = math.floor(val)
        updateTelemetry(nil, #Waypoints)
    end, 3)

    createSliderRow(settingsPage, "SpeedSlider", "Playback Speed", 0.5, 3.0, Config.SpeedMultiplier, "%.2fx", function(val)
        Config.SpeedMultiplier = math.floor(val * 100) / 100
        updateTelemetry(nil, #Waypoints)
    end, 4)

    createSectionHeader(settingsPage, "Hardware Bridge & Integration", 5)

    createToggleRow(settingsPage, "BridgeToggle", "External Macro Bridge (.NET)", activeTheme.PlayActive, function(state)
        Config.UseExternalBridge = state
        showToast("Hardware Bridge: " .. (state and "Enabled" or "Disabled"))
    end, 6, Config.UseExternalBridge)

    createSectionHeader(settingsPage, "Display & Visualizer", 7)

    createToggleRow(settingsPage, "StatusHUDToggle", "Persistent Status Bar (Draggable)", activeTheme.Accent, function(state)
        Config.StatusHUDEnabled = state
        statusHUD.Visible = state
    end, 8, Config.StatusHUDEnabled)

    createToggleRow(settingsPage, "RealtimeVisToggle", "Realtime Visual Rendering", activeTheme.Accent, function(state)
        Config.RealtimeVisualizer = state
    end, 9, Config.RealtimeVisualizer)

    createToggleRow(settingsPage, "WaypointLabelsToggle", "3D Waypoint Tags", activeTheme.Accent, function(state)
        Config.WaypointLabelsEnabled = state
        renderVisualPath(Waypoints)
    end, 10, Config.WaypointLabelsEnabled)

    createToggleRow(settingsPage, "VisualizerToggle", "3D Workspace Visualizer", activeTheme.Accent, function(state)
        Config.VisualizerEnabled = state
        if state then renderVisualPath(Waypoints) else clearVisuals() end
    end, 11, Config.VisualizerEnabled)

    createSliderRow(settingsPage, "OrbOpacitySlider", "Visualizer Orb Opacity", 0.0, 0.8, Config.VisualizerOpacity, "Opacity: %.2f", function(val)
        Config.VisualizerOpacity = math.floor(val * 100) / 100
        renderVisualPath(Waypoints)
    end, 12)

    createSectionHeader(settingsPage, "Keybind Shortcuts", 13)

    local activeBindingKey = nil
    local function createKeybindRow(labelText, actionKeyName, order)
        local row = Instance.new("Frame")
        row.Name = "Hotkey_" .. actionKeyName
        row.LayoutOrder = order
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = activeTheme.Surface
        row.BackgroundTransparency = 0.5
        row.BorderSizePixel = 0
        row.Parent = settingsPage
        registerElement("Surface", row, "BackgroundColor3")

        local kCorner = Instance.new("UICorner")
        kCorner.CornerRadius = UDim.new(0, 8)
        kCorner.Parent = row

        local kStroke = Instance.new("UIStroke")
        kStroke.Thickness = 1
        kStroke.Color = activeTheme.Border
        kStroke.Transparency = 0.5
        kStroke.Parent = row
        registerElement("Border", kStroke, "Color")

        local kPadding = Instance.new("UIPadding")
        kPadding.PaddingLeft = UDim.new(0, 14)
        kPadding.PaddingRight = UDim.new(0, 14)
        kPadding.Parent = row

        local kLabel = Instance.new("TextLabel")
        kLabel.Size = UDim2.new(1, -120, 1, 0)
        kLabel.BackgroundTransparency = 1
        kLabel.Text = labelText
        kLabel.TextColor3 = activeTheme.TextPrimary
        kLabel.TextSize = 12
        kLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        kLabel.TextXAlignment = Enum.TextXAlignment.Left
        kLabel.Parent = row
        registerElement("TextPrimary", kLabel, "TextColor3")

        local kBtn = Instance.new("TextButton")
        kBtn.Size = UDim2.new(0, 100, 0, 26)
        kBtn.Position = UDim2.new(1, -100, 0.5, -13)
        kBtn.BackgroundColor3 = activeTheme.ToggleOff
        kBtn.BackgroundTransparency = 0.2
        kBtn.BorderSizePixel = 0
        kBtn.AutoButtonColor = false
        kBtn.Text = Keybinds[actionKeyName].Name
        kBtn.TextColor3 = activeTheme.TextPrimary
        kBtn.TextSize = 11
        kBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
        kBtn.Parent = row
        registerElement("ToggleOff", kBtn, "BackgroundColor3")
        registerElement("TextPrimary", kBtn, "TextColor3")

        local kBtnCorner = Instance.new("UICorner")
        kBtnCorner.CornerRadius = UDim.new(0, 6)
        kBtnCorner.Parent = kBtn

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
            showToast(string.format("%s set to: %s", activeBindingKey, input.KeyCode.Name))
            activeBindingKey = nil
            return
        end

        if not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Keybinds.ToggleMenu then
                setGuiVisible(not isGuiOpen)
            elseif input.KeyCode == Keybinds.ToggleRecord then
                if recordToggleControl and typeof(recordToggleControl.Get) == "function" then 
                    recordToggleControl.Set(not recordToggleControl.Get()) 
                end
            elseif input.KeyCode == Keybinds.TogglePlay then
                if playToggleControl and typeof(playToggleControl.Get) == "function" then 
                    playToggleControl.Set(not playToggleControl.Get()) 
                end
            elseif input.KeyCode == Keybinds.UndoNode then
                undoLastNode()
            end
        end
    end)
    table.insert(scriptConnections, inputConnection)

    createSectionHeader(settingsPage, "Theme Selector & Studio", 18)

    local function applyTheme(themeName, customPalette)
        currentThemeName = themeName
        activeTheme = customPalette or THEMES[themeName]

        for _, item in ipairs(themeElements.Background) do item.Object[item.Property] = activeTheme.Background end
        for _, item in ipairs(themeElements.Surface) do item.Object[item.Property] = activeTheme.Surface end
        for _, item in ipairs(themeElements.Border) do item.Object[item.Property] = activeTheme.Border end
        for _, item in ipairs(themeElements.AccentText) do item.Object[item.Property] = activeTheme.Accent end
        for _, item in ipairs(themeElements.AccentBg) do item.Object[item.Property] = activeTheme.Accent end
        for _, item in ipairs(themeElements.TextPrimary) do item.Object[item.Property] = activeTheme.TextPrimary end
        for _, item in ipairs(themeElements.TextSecondary) do item.Object[item.Property] = activeTheme.TextSecondary end
        for _, item in ipairs(themeElements.ToggleOff) do item.Object[item.Property] = activeTheme.ToggleOff end

        if activeTheme.GradientEnabled then
            bgGradient.Enabled = true
            bgGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, activeTheme.Background),
                ColorSequenceKeypoint.new(1, activeTheme.GradientColor or activeTheme.Accent)
            })
        else
            bgGradient.Enabled = false
        end

        for _, t in ipairs(activeToggles) do t.UpdateTheme() end
        showToast("Theme: " .. themeName)
    end

    local themeOrder = { "Midnight Blue", "Dark Charcoal" }
    for idx, name in ipairs(themeOrder) do
        local themePreset = THEMES[name]
        local themeOption = Instance.new("TextButton")
        themeOption.Name = "Theme_" .. name
        themeOption.LayoutOrder = 18 + idx
        themeOption.Size = UDim2.new(1, 0, 0, 36)
        themeOption.BackgroundColor3 = themePreset.Surface
        themeOption.BackgroundTransparency = 0.4
        themeOption.BorderSizePixel = 0
        themeOption.AutoButtonColor = false
        themeOption.Text = "   " .. name
        themeOption.TextColor3 = themePreset.TextPrimary
        themeOption.TextSize = 12
        themeOption.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        themeOption.TextXAlignment = Enum.TextXAlignment.Left
        themeOption.Parent = settingsPage

        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(0, 6)
        tCorner.Parent = themeOption

        local previewDot = Instance.new("Frame")
        previewDot.Size = UDim2.new(0, 12, 0, 12)
        previewDot.Position = UDim2.new(1, -22, 0.5, -6)
        previewDot.BackgroundColor3 = themePreset.Accent
        previewDot.BorderSizePixel = 0
        previewDot.Parent = themeOption
        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UDim.new(1, 0)
        pCorner.Parent = previewDot

        themeOption.MouseButton1Click:Connect(function()
            applyTheme(name)
        end)
    end

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
    terminateProcess = function()
        stopRecording(); stopPlayback(); clearVisuals()
        for _, conn in ipairs(scriptConnections) do
            if conn and typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
        end
        table.clear(scriptConnections)
        if visualizerFolder then visualizerFolder:Destroy() end
        _G.Autofarm_Control = nil
        if screenGui then screenGui:Destroy() end
    end

    local terminateBtn = Instance.new("TextButton")
    terminateBtn.Name = "TerminateButton"
    terminateBtn.LayoutOrder = 10
    terminateBtn.Size = UDim2.new(1, 0, 0, 38)
    terminateBtn.BackgroundColor3 = Color3.fromRGB(45, 20, 24)
    terminateBtn.BackgroundTransparency = 0.3
    terminateBtn.BorderSizePixel = 0
    terminateBtn.Text = "Terminate & Unload Script"
    terminateBtn.TextColor3 = Color3.fromRGB(255, 95, 95)
    terminateBtn.TextSize = 12
    terminateBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold)
    terminateBtn.Parent = safetyPage

    local termCorner = Instance.new("UICorner")
    termCorner.CornerRadius = UDim.new(0, 8)
    termCorner.Parent = terminateBtn

    terminateBtn.MouseButton1Click:Connect(function() terminateProcess() end)

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Size = UDim2.new(0, 18, 0, 18)
    resizeHandle.Position = UDim2.new(1, -18, 1, -18)
    resizeHandle.BackgroundTransparency = 1
    resizeHandle.Text = "◢"
    resizeHandle.TextColor3 = activeTheme.TextSecondary
    resizeHandle.Parent = mainFrame
    registerElement("TextSecondary", resizeHandle, "TextColor3")

    local dragging, dragStartPos, frameStartPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStartPos = input.Position
            frameStartPos = mainFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    local dragChangeConn = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStartPos
            mainFrame.Position = UDim2.new(frameStartPos.X.Scale, frameStartPos.X.Offset + delta.X, frameStartPos.Y.Scale, frameStartPos.Y.Offset + delta.Y)
        end
    end)
    table.insert(scriptConnections, dragChangeConn)
end

local currentLoopCount = 0 -- ADD THIS LINE HERE
updateTelemetry = function(currentNode, totalNodes)
    totalNodes = totalNodes or 0
    local loopTargetStr = (Config.TargetLoops == 0) and "Inf" or tostring(Config.TargetLoops)
    if currentNode and totalNodes > 0 then
        nodeStatsLabel.Text = string.format("Node: %d/%d | Loop: %d/%s", currentNode, totalNodes, currentLoopCount, loopTargetStr)
        hudNodeLabel.Text = string.format("Node: %d/%d", currentNode, totalNodes)
        local progress = math.clamp(currentNode / totalNodes, 0, 1)
        TweenService:Create(progressBar, TweenInfo.new(0.1), { Size = UDim2.new(progress, 0, 1, 0) }):Play()
    else
        nodeStatsLabel.Text = string.format("Waypoints: %d | Loop: %d/%s", totalNodes, currentLoopCount, loopTargetStr)
        hudNodeLabel.Text = string.format("Nodes: %d", totalNodes)
        progressBar.Size = UDim2.new(0, 0, 1, 0)
    end
    routeModeLabel.Text = string.format("%s (%.2fx)", Config.PlaybackMode, Config.SpeedMultiplier)
    hudLoopLabel.Text = string.format("Loop: %d/%s | %.1fx", currentLoopCount, loopTargetStr, Config.SpeedMultiplier)
end

local function getVisualizerNode(index)
    if visualizerPool.Nodes[index] then return visualizerPool.Nodes[index] end
    local node = Instance.new("Part")
    node.Shape = Enum.PartType.Ball; node.Anchored = true; node.CanCollide = false
    node.Material = Enum.Material.Neon; node.CastShadow = false; node.Parent = visualizerFolder
    visualizerPool.Nodes[index] = node
    return node
end

local function getVisualizerBeam(index)
    if visualizerPool.Beams[index] then return visualizerPool.Beams[index] end
    local beam = Instance.new("Part")
    beam.Anchored = true; beam.CanCollide = false; beam.Material = Enum.Material.Neon
    beam.Color = Color3.fromRGB(120, 120, 140); beam.CastShadow = false; beam.Parent = visualizerFolder
    visualizerPool.Beams[index] = beam
    return beam
end

local function getVisualizerLabel(node, index)
    if visualizerPool.Labels[index] then 
        visualizerPool.Labels[index].Adornee = node
        return visualizerPool.Labels[index].Tag
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = node; billboard.Size = UDim2.new(0, 48, 0, 18)
    billboard.StudsOffset = Vector3.new(0, 1.2, 0); billboard.AlwaysOnTop = true
    billboard.Parent = visualizerFolder
    
    local tag = Instance.new("TextLabel")
    tag.Size = UDim2.new(1, 0, 1, 0); tag.BackgroundTransparency = 1
    tag.TextSize = 10; tag.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    tag.Parent = billboard

    visualizerPool.Labels[index] = { Billboard = billboard, Tag = tag }
    return tag
end

renderVisualPath = function(waypointsList)
    clearVisuals()
    if not Config.VisualizerEnabled or #waypointsList == 0 then return end

    local prevNode = nil
    for i, data in ipairs(waypointsList) do
        local node = getVisualizerNode(i)
        node.Size = (i == 1 or i == #waypointsList) and Vector3.new(1.1, 1.1, 1.1) or Vector3.new(0.7, 0.7, 0.7)
        node.CFrame = CFrame.new(data.pos)
        node.Transparency = Config.VisualizerOpacity

        if i == 1 then node.Color = Color3.fromRGB(0, 255, 128)
        elseif i == #waypointsList then node.Color = Color3.fromRGB(255, 60, 60)
        elseif data.isMouseClick then node.Color = Color3.fromRGB(255, 0, 80)
        elseif data.action or data.actionPromptName or data.isInteractionNode then node.Color = Color3.fromRGB(0, 170, 255)
        elseif data.pauseDuration and data.pauseDuration > 0.5 then node.Color = Color3.fromRGB(255, 215, 0)
        elseif data.jump then node.Color = Color3.fromRGB(255, 170, 0)
        elseif data.isSprinting then node.Color = Color3.fromRGB(255, 80, 180)
        else node.Color = Color3.fromRGB(50, 220, 120) end

        if Config.WaypointLabelsEnabled then
            local tag = getVisualizerLabel(node, i)
            tag.Parent.Enabled = true
            if i == 1 then tag.Text = "[START]"; tag.TextColor3 = Color3.fromRGB(0, 255, 128)
            elseif i == #waypointsList then tag.Text = "[END]"; tag.TextColor3 = Color3.fromRGB(255, 80, 80)
            elseif data.isMouseClick then tag.Text = string.format("[MB1 %.1fs]", data.clickDuration or 0); tag.TextColor3 = Color3.fromRGB(255, 0, 80)
            elseif data.action or data.actionPromptName or data.isInteractionNode then tag.Text = string.format("[E %.1fs]", data.actionHoldDuration or 0); tag.TextColor3 = Color3.fromRGB(0, 200, 255)
            elseif data.pauseDuration and data.pauseDuration > 0.5 then tag.Text = string.format("[%.1fs]", data.pauseDuration); tag.TextColor3 = Color3.fromRGB(255, 215, 0)
            else tag.Text = tostring(i); tag.TextColor3 = Color3.fromRGB(255, 255, 255) end
        else
            if visualizerPool.Labels[i] then visualizerPool.Labels[i].Billboard.Enabled = false end
        end

        if prevNode then
            local beam = getVisualizerBeam(i)
            local distance = (data.pos - prevNode.Position).Magnitude
            if distance > 0.1 then
                beam.Size = Vector3.new(0.12, 0.12, distance)
                beam.CFrame = CFrame.lookAt(prevNode.Position, data.pos) * CFrame.new(0, 0, -distance / 2)
                beam.Transparency = math.clamp(Config.VisualizerOpacity + 0.3, 0, 0.9)
            end
        end
        prevNode = node
    end
    
    for i = #waypointsList + 1, #visualizerPool.Labels do
        visualizerPool.Labels[i].Billboard.Enabled = false
    end
end

-- Kinematics & Record Engine State
local Waypoints = {}
local isRecording = false
local isPlaying = false
local jumpConnection, keyConnection, keyEndConnection, stateConnection, deathConnection
local jumpTriggered = false
local lastWaypointTime = 0
local holdStartTick = nil
local mb1StartTick = nil

local function hookDeathFailSafe()
    if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
    local char, _, hum = getCharacter()
    if hum then
        deathConnection = hum.Died:Connect(function()
            if (isRecording or isPlaying) and Config.EmergencyLeaveOnDeath then game:Shutdown() end
        end)
    end
end
player.CharacterAdded:Connect(function() task.wait(0.5); hookDeathFailSafe() end)
hookDeathFailSafe()

local function hookInputListeners()
    if jumpConnection then jumpConnection:Disconnect(); jumpConnection = nil end
    if stateConnection then stateConnection:Disconnect(); stateConnection = nil end
    if keyConnection then keyConnection:Disconnect(); keyConnection = nil end
    if keyEndConnection then keyEndConnection:Disconnect(); keyEndConnection = nil end

    jumpConnection = UserInputService.JumpRequest:Connect(function()
        if isRecording then jumpTriggered = true end
    end)

    keyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if isRecording then
            if input.KeyCode == Enum.KeyCode.E then
                holdStartTick = tick()
            elseif Config.RecordMouseClicks and input.UserInputType == Enum.UserInputType.MouseButton1 then
                mb1StartTick = tick()
            end
        end
    end)

    keyEndConnection = UserInputService.InputEnded:Connect(function(input)
        if isRecording then
            if input.KeyCode == Enum.KeyCode.E and holdStartTick then
                local rawDuration = tick() - holdStartTick
                local finalDuration = math.max(rawDuration, 0.1)
                holdStartTick = nil

                local pos = getEntityPosition()
                if not pos then return end
                local now = tick()
                local _, _, h = getCharacter()
                local cam = workspace.CurrentCamera
                local aimPos = pos + (cam and (cam.CFrame.LookVector * 3.5) or Vector3.zero)

                table.insert(Waypoints, {
                    pos = pos,
                    promptPos = aimPos,
                    jump = false,
                    pauseDuration = 0,
                    speed = h and h.WalkSpeed or 16,
                    isSprinting = h and (h.WalkSpeed > 17) or false,
                    isInteractionNode = true,
                    actionHoldDuration = math.floor((finalDuration + 0.1) * 100) / 100,
                    interactionCount = 1,
                    interClickDelay = 0.2,
                    delay = now - lastWaypointTime
                })
                lastWaypointTime = now
                updateTelemetry(nil, #Waypoints)
                if Config.RealtimeVisualizer then renderVisualPath(Waypoints) end
                showToast(string.format("Interaction Stamped (%.1fs)", finalDuration))
                
            elseif Config.RecordMouseClicks and input.UserInputType == Enum.UserInputType.MouseButton1 and mb1StartTick then
                local rawDuration = tick() - mb1StartTick
                local finalDuration = math.max(rawDuration, 0.05)
                mb1StartTick = nil
                
                local pos = getEntityPosition()
                if not pos then return end
                local now = tick()
                local _, _, h = getCharacter()
                
                table.insert(Waypoints, {
                    pos = pos,
                    isMouseClick = true,
                    clickDuration = math.floor((finalDuration) * 100) / 100,
                    jump = false,
                    pauseDuration = 0,
                    speed = h and h.WalkSpeed or 16,
                    delay = now - lastWaypointTime
                })
                lastWaypointTime = now
                updateTelemetry(nil, #Waypoints)
                if Config.RealtimeVisualizer then renderVisualPath(Waypoints) end
                showToast(string.format("Mouse Click Stamped (%.2fs)", finalDuration))
            end
        end
    end)
    table.insert(scriptConnections, keyEndConnection)

    local _, _, hum = getCharacter()
    if hum then
        stateConnection = hum.StateChanged:Connect(function(oldState, newState)
            if isRecording and newState == Enum.HumanoidStateType.Jumping then jumpTriggered = true end
        end)
    end
end

stopRecording = function()
    isRecording = false
    jumpTriggered = false
    holdStartTick = nil
    mb1StartTick = nil
    if jumpConnection then jumpConnection:Disconnect(); jumpConnection = nil end
    if keyConnection then keyConnection:Disconnect(); keyConnection = nil end
    if keyEndConnection then keyEndConnection:Disconnect(); keyEndConnection = nil end
    if stateConnection then stateConnection:Disconnect(); stateConnection = nil end
    if recordToggleControl and typeof(recordToggleControl.Get) == "function" and recordToggleControl.Get() then
        recordToggleControl.Set(false, true)
    end
    updateStateBadge("IDLE", Color3.fromRGB(60, 65, 80))
    renderVisualPath(Waypoints)
    updateTelemetry(nil, #Waypoints)
    playSoundFeedback(0.9)
    showToast(string.format("Recording stopped (%d nodes)", #Waypoints))
end

startRecording = function()
    if isRecording then return end
    if isPlaying then
        if playToggleControl and typeof(playToggleControl.Set) == "function" then playToggleControl.Set(false, false) end
    end

    local initialPos = nil
    for _ = 1, 30 do
        initialPos = getEntityPosition()
        if initialPos then break end
        task.wait(0.1)
    end

    if not initialPos then
        triggerErrorModal("ERR_NO_PHYSICAL_ROOT", "Could not locate a valid physical root part on your character model.")
        if recordToggleControl and typeof(recordToggleControl.Set) == "function" then recordToggleControl.Set(false, true) end
        return
    end

    Waypoints = {}
    clearVisuals()
    isRecording = true
    jumpTriggered = false
    holdStartTick = nil
    mb1StartTick = nil
    currentLoopCount = 0
    lastWaypointTime = tick()
    updateStateBadge("REC", activeTheme.RecordActive)
    playSoundFeedback(1.2)
    showToast("Recording started...")

    hookInputListeners()
    local _, _, hum = getCharacter()

    table.insert(Waypoints, { pos = initialPos, jump = false, pauseDuration = 0, speed = hum and hum.WalkSpeed or 16, delay = 0.08 })
    updateTelemetry(nil, #Waypoints)
    if Config.RealtimeVisualizer then renderVisualPath(Waypoints) end

    task.spawn(function()
        local lastRecordedPos = initialPos
        local standingStillTime = 0

        while isRecording do
            local pos = getEntityPosition()
            if pos then
                local _, _, h = getCharacter()
                local distMoved = (pos - lastRecordedPos).Magnitude
                local now = tick()
                local stampedJump = jumpTriggered
                jumpTriggered = false

                if distMoved > 0.4 or stampedJump then
                    standingStillTime = 0
                    table.insert(Waypoints, {
                        pos = pos, jump = stampedJump, pauseDuration = 0,
                        speed = h and h.WalkSpeed or 16, isSprinting = h and (h.WalkSpeed > 17) or false,
                        delay = now - lastWaypointTime
                    })
                    lastRecordedPos = pos
                    lastWaypointTime = now
                    updateTelemetry(nil, #Waypoints)
                    if Config.RealtimeVisualizer then renderVisualPath(Waypoints) end
                else
                    standingStillTime = standingStillTime + 0.08
                    if #Waypoints > 0 and standingStillTime > 0.6 then
                        Waypoints[#Waypoints].pauseDuration = math.floor(standingStillTime * 10) / 10
                    end
                end
            end
            task.wait(0.08)
        end
    end)
end

stopPlayback = function()
    isPlaying = false
    setHaloTarget(nil)
    local _, root, hum = getCharacter()
    if hum and root then hum:MoveTo(root.Position) elseif root then root.AssemblyLinearVelocity = Vector3.zero end
    if playToggleControl and typeof(playToggleControl.Get) == "function" and playToggleControl.Get() then
        playToggleControl.Set(false, true)
    end
    updateStateBadge("IDLE", Color3.fromRGB(60, 65, 80))
    updateTelemetry(nil, #Waypoints)
    showToast("Playback stopped.")
end

local function resolveAndTriggerPrompt(data, root)
    local targetPosition = data.promptPos or data.pos
    local camera = workspace.CurrentCamera
    local _, _, hum = getCharacter()

    if hum then hum:Move(Vector3.zero, false) end
    if root then root.AssemblyLinearVelocity = Vector3.zero end

    -- STRICT RECORDED DURATION INJECTION
    local baseHoldTimeMs = data.actionHoldDuration and math.floor(data.actionHoldDuration * 1000) or 200
    local bufferedHoldTimeMs = baseHoldTimeMs + 150 -- 150ms buffer for hardware bridge
    local bufferedHoldTimeSec = bufferedHoldTimeMs / 1000
    local totalTimes = math.max(data.interactionCount or 1, 1)

    for count = 1, totalTimes do
        if not isPlaying then break end

        if root and targetPosition then root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)) end
        if camera and targetPosition then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition) end
        
        for _ = 1, 5 do RunService.RenderStepped:Wait() end

        print(string.format("📡 [ManniskaFarm] Dispatching HOLD_E:%d to Macro...", bufferedHoldTimeMs))
        sendExternalMacroCommand("E", bufferedHoldTimeMs)

        if VirtualInputManager then pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) end

        local startTime = tick()
        while (tick() - startTime) < bufferedHoldTimeSec and isPlaying do
            if camera and targetPosition then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition) end
            RunService.RenderStepped:Wait()
        end

        if VirtualInputManager then pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end) end

        if totalTimes > 1 and count < totalTimes then
            task.wait(math.max((data.interClickDelay or 0.2) / Config.SpeedMultiplier, 0.2))
        end
    end
end

local function navigateToPoint(targetPosition, maxSpeed)
    local _, liveRoot, _ = getCharacter()
    if not liveRoot then return false end

    local currentPos = liveRoot.Position
    local totalDelta = Vector3.new(targetPosition.X - currentPos.X, 0, targetPosition.Z - currentPos.Z)
    local totalDistance = totalDelta.Magnitude

    if totalDistance <= (2.4 * Config.SpeedMultiplier) then return true end

    local stepCount = math.max(math.ceil(totalDistance / 2.0), 1)
    local stepVector = (targetPosition - currentPos) / stepCount

    for stepIdx = 1, stepCount do
        if not isPlaying then return false end
        local subTarget = currentPos + (stepVector * stepIdx)
        local subTimeout = 0

        while isPlaying do
            local _, curR, curH = getCharacter()
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

startPlayback = function()
    if isPlaying or #Waypoints == 0 then return end
    if isRecording then
        if recordToggleControl and typeof(recordToggleControl.Get) == "function" then recordToggleControl.Set(false, false) end
    end

    local _, root, _ = getCharacter()
    if not root then
        triggerErrorModal("ERR_PLAYBACK_STALL", "Cannot start playback: No character root part found.")
        if playToggleControl and typeof(playToggleControl.Set) == "function" then playToggleControl.Set(false, true) end
        return
    end

    isPlaying = true
    currentLoopCount = 0
    updateStateBadge("PLAY", activeTheme.PlayActive)
    playSoundFeedback(1.2)
    showToast("Playback started: " .. Config.PlaybackMode)

    task.spawn(function()
        local directionForward = (Config.PlaybackMode ~= "Reverse")

        while isPlaying do
            local _, curRoot, hum = getCharacter()
            if not curRoot then break end

            local startIndex = directionForward and 1 or #Waypoints
            local endIndex = directionForward and #Waypoints or 1
            local step = directionForward and 1 or -1

            local initialNode = Waypoints[startIndex]
            if initialNode then
                local startDist = (Vector3.new(initialNode.pos.X, 0, initialNode.pos.Z) - Vector3.new(curRoot.Position.X, 0, curRoot.Position.Z)).Magnitude
                if startDist > 3.0 then navigateToPoint(initialNode.pos, 16 * Config.SpeedMultiplier) end
            end

            local i = startIndex
            while (directionForward and i <= endIndex) or (not directionForward and i >= endIndex) do
                if not isPlaying then break end
                local data = Waypoints[i]
                if not data then break end

                updateTelemetry(i, #Waypoints)
                setHaloTarget(data.pos)

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
                        sendExternalMacroCommand("MB1", holdTimeMs)
                        task.wait((data.clickDuration or 0) + 0.1)
                    end

                    if data.isInteractionNode or data.promptPos then
                        resolveAndTriggerPrompt(data, curRoot)
                    end

                    if data.pauseDuration and data.pauseDuration > 0.3 and not data.isInteractionNode and not data.isMouseClick then
                        local pauseStart = tick()
                        local totalPause = data.pauseDuration / Config.SpeedMultiplier
                        while (tick() - pauseStart) < totalPause and isPlaying do
                            local _, stillRoot, stillHum = getCharacter()
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
                    local checkPos = getEntityPosition() or curRoot.Position

                    while isPlaying do
                        local _, dynamicRoot, dynamicHum = getCharacter()
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

            currentLoopCount = currentLoopCount + 1
            updateTelemetry(nil, #Waypoints)
            playSoundFeedback(1.5)

            if Config.TargetLoops > 0 and currentLoopCount >= Config.TargetLoops then
                showToast(string.format("Completed %d loop(s). Stopping.", Config.TargetLoops))
                break
            end

            if Config.PlaybackMode == "One-Shot" or Config.PlaybackMode == "Reverse" then break
            elseif Config.PlaybackMode == "Ping-Pong" then directionForward = not directionForward end
        end
        stopPlayback()
    end)
end

undoLastNode = function()
    if #Waypoints > 0 then
        table.remove(Waypoints)
        renderVisualPath(Waypoints)
        updateTelemetry(nil, #Waypoints)
        showToast(string.format("Undid node #%d", #Waypoints + 1))
        playSoundFeedback(0.8)
    else
        showToast("No nodes to undo.")
    end
end

clearWaypoints = function()
    Waypoints = {}
    clearVisuals()
    currentLoopCount = 0
    updateTelemetry(nil, 0)
    showToast("Route waypoints cleared.")
end

copyRouteToClipboard = function()
    if #Waypoints == 0 then showToast("No route data to export."); return end
    local exportTable = {}
    for _, wp in ipairs(Waypoints) do
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
    if setclipboard then setclipboard(jsonString); showToast("Route JSON copied to clipboard!")
    else showToast("Clipboard API unavailable.") end
end

saveRouteToFile = function(fileName)
    local name = (fileName and fileName ~= "") and fileName or Config.FileName
    if not (writefile and isfile) then triggerErrorModal("ERR_STORAGE_WRITE", "Your executor does not support the 'writefile' API."); return end
    local exportTable = {}
    for _, wp in ipairs(Waypoints) do
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
    writefile(name, HttpService:JSONEncode(exportTable))
    showToast("Saved route to: " .. name)
end

loadRouteFromFile = function(fileName)
    local name = (fileName and fileName ~= "") and fileName or Config.FileName
    if not (readfile and isfile and isfile(name)) then triggerErrorModal("ERR_FILE_NOT_FOUND", "Could not locate file '" .. name .. "'"); return end
    local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(name)) end)
    if success and typeof(decoded) == "table" then
        Waypoints = {}
        for _, rawWp in ipairs(decoded) do
            table.insert(Waypoints, {
                pos = Vector3.new(rawWp.pos[1], rawWp.pos[2], rawWp.pos[3]),
                promptPos = rawWp.promptPos and Vector3.new(rawWp.promptPos[1], rawWp.promptPos[2], rawWp.promptPos[3]) or nil,
                jump = rawWp.jump, pauseDuration = rawWp.pauseDuration or 0,
                speed = rawWp.speed or 16, isSprinting = rawWp.isSprinting or false, delay = rawWp.delay,
                isInteractionNode = rawWp.isInteractionNode or false, interactionCount = rawWp.interactionCount or 1,
                interClickDelay = rawWp.interClickDelay or 0.15, actionHoldDuration = rawWp.actionHoldDuration or 0,
                isMouseClick = rawWp.isMouseClick or false, clickDuration = rawWp.clickDuration or 0
            })
        end
        renderVisualPath(Waypoints); currentLoopCount = 0; updateTelemetry(nil, #Waypoints)
        showToast(string.format("Loaded %d waypoints from %s", #Waypoints, name))
    else triggerErrorModal("ERR_JSON_PARSE", "Failed to deserialize route data. The JSON formatting may be corrupted.") end
end

_G.Autofarm_Control = {
    ToggleRecord = function(state) if state then startRecording() else stopRecording() end end,
    TogglePlay = function(state) if state then startPlayback() else stopPlayback() end end,
    Clear = clearWaypoints, Undo = undoLastNode, GetCount = function() return #Waypoints end, GetLoops = function() return currentLoopCount end,
    Save = saveRouteToFile, Load = loadRouteFromFile, Export = copyRouteToClipboard, Terminate = terminateProcess, Config = Config, Keybinds = Keybinds
}

print("🚀 Autofarm V13.1 (Strict Timing & Click Recorder) Loaded.")
