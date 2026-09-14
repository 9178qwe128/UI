--[[
    Roblox Executor 横向玻璃 GUI — 抓包相关
    --------------------------------------------------
    环境:   Executor / 漏洞注入 , Luau + 原生 UI (ScreenGui)
    布局:   横向 —— 左侧功能大类列表 + 右侧对应面板
    特效:   UI 半透明毛玻璃 (只透明 UI, 不是全屏透明)
    功能:   顶部栏拖动 / 最小化折叠成悬浮球 / 大类切换
    适配:   手机触屏 (按钮尺寸 + ScrollView touch scroll)
]]

-- ─────────── 配置区 ───────────
local Config = {
    GlassColor   = Color3.fromRGB(22, 26, 36),
    GlassTrans   = 0.42,              -- 玻璃块透明度(值越大越透明)
    BorderColor  = Color3.fromRGB(255, 255, 255),
    BorderTrans  = 0.75,              -- 描边透明度
    Corner       = UDim.new(0, 14),   -- 圆角
    Accent       = Color3.fromRGB(80, 150, 255),
    TextColor    = Color3.fromRGB(235, 238, 245),
    SubText      = Color3.fromRGB(140, 150, 170),
    PanelBG      = Color3.fromRGB(15, 18, 26),
    PanelBGTrans = 0.55,
}

local Http = game:GetService("HttpService")

-- ============================================================
--  UI 构建助手
-- ============================================================
local function New(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function GlassFrame(name, parent)
    local f = New("Frame", {
        Name = name,
        BackgroundColor3 = Config.GlassColor,
        BackgroundTransparency = Config.GlassTrans,
        BorderSizePixel = 0,
    }, parent)
    local grad = New("UICorner", { CornerRadius = Config.Corner }, f)
    -- 细描边模拟玻璃高光
    New("UIStroke", {
        Color = Config.BorderColor,
        Transparency = Config.BorderTrans,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, f)
    return f
end

local function TextBtn(text, size, parent, cb)
    local b = New("TextButton", {
        Text = text,
        Size = size,
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextColor3 = Config.TextColor,
        TextSize = 15,
        TextScaled = true,
        AutoButtonColor = false,
    }, parent)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
    New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
    b.MouseEnter:Connect(function()
        b.BackgroundTransparency = 0.7
    end)
    b.MouseLeave:Connect(function()
        b.BackgroundTransparency = 1
    end)
    b.Activated:Connect(cb)
    return b
end

-- 生成面板内一格
local function Section(title, parent)
    local box = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = Config.PanelBG,
        BackgroundTransparency = Config.PanelBGTrans,
        BorderSizePixel = 0,
        LayoutOrder = 1,
    }, parent)
    New("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
    New("UIStroke", {
        Color = Config.BorderColor, Transparency = 0.85, Thickness = 1,
    }, box)
    New("TextLabel", {
        Text = title,
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 0, 0, 0),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextColor3 = Config.Accent,
        TextSize = 14,
    }, box)
    -- 内容容器
    local content = New("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        Position = UDim2.new(0, 10, 0, 28),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
    }, box)
    return box, content
end

-- 包装到绝对尺寸(供 ListLayout 自动撑高)
local function AutoSize(frame, gap)
    local lay = New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap or 10),
    }, frame)
    return frame
end

-- ============================================================
--  数据源 ── ★ 在这里填你的 rspy 抓包数据 ★
-- ============================================================
-- 每个接口:
--   name   显示名
--   url    目标地址
--   method 请求方法
--   body   提交的 body 模板(JSON 字符串, 用 {0} 占位)
local PacketDB = {
    -- ================= 真实包粘贴区 =================
    -- 示例占位, 拿到 rspy 数据后替换/增删:
    {
        name = "打生物接口",
        url = "https://example.com/api/battle",
        method = "POST",
        body = [[{"monster_id":{0},"dmg":1000}]],
    },
}
-- 供「重发」面板实时增删
local ActivePackets = {}

-- ============================================================
--  主体 UI 构建
-- ============================================================
local Player = game:GetService("Players").LocalPlayer
local mouse = Player:GetMouse()

local sg = New("ScreenGui", {
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, Player:WaitForChild("PlayerGui"))

-- 全局点击拦截(拖拽/折叠不误触里面)
local blocker = New("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    ZIndex = 0,
    Active = false,
}, sg)

-- ── 主玻璃容器 ──
local Main = GlassFrame("Main", sg)
Main.Size = UDim2.new(0, 560, 0, 380)
Main.Position = UDim2.new(0.5, -280, 0.5, -150)
Main.AnchorPoint = Vector2.new(0, 0)

-- ── 顶部栏(拖动 + 最小化) ──
local TitleBar = New("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundTransparency = 1,
    ZIndex = 10,
}, Main)
New("TextLabel", {
    Text = "★ 抓包工具",
    Size = UDim2.new(0, 140, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextColor3 = Config.TextColor,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextSize = 16,
}, TitleBar)

local MinBtn = New("TextButton", {
    Text = "—",
    Size = UDim2.new(0, 34, 0, 26),
    Position = UDim2.new(1, -84, 0, 0),
    AnchorPoint = Vector2.new(1, 0),
    Font = Enum.Font.GothamBold, TextColor3 = Config.TextColor, TextSize = 18,
    BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.4,
    AutoButtonColor = false, BorderSizePixel = 0,
}, TitleBar)
New("UICorner", { CornerRadius = UDim.new(0, 7) }, MinBtn)

local CloseBtn = New("TextButton", {
    Text = "×",
    Size = UDim2.new(0, 34, 0, 26),
    Position = UDim2.new(1, -46, 0, 0),
    AnchorPoint = Vector2.new(1, 0),
    Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 110, 120), TextSize = 20,
    BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.4,
    AutoButtonColor = false, BorderSizePixel = 0,
}, TitleBar)
New("UICorner", { CornerRadius = UDim.new(0, 7) }, CloseBtn)

-- 拖动
local dragging, startPos, startMouse
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        startPos = Main.Position
        startMouse = input.Position
    end
end)
TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
        local delta = input.Position - startMouse
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X / 2,
                                  startPos.Y.Scale, startPos.Y.Offset + delta.Y / 2)
    end
end)
TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- ── 左侧工具栏(大类列表) ──
local SideW = 118
local Side = New("Frame", {
    Size = UDim2.new(0, SideW, 1, -40),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundTransparency = 1,
}, Main)
local SideScroll = New("ScrollingFrame", {
    Size = UDim2.new(1, -10, 1, -6),
    Position = UDim2.new(0, 5, 0, 3),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 2, 0),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, Side)
local SideList = New("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
}, SideScroll)

local Categories = {
    { id = "packet",  label = "抓包" },
    { id = "setting", label = "设置" },
}
local sideBtns = {}
local currentCat = "packet"

-- ── 右侧面板容器 ──
local PanelHost = New("Frame", {
    Size = UDim2.new(1, -SideW - 14, 1, -52),
    Position = UDim2.new(1, -10, 1, -8),
    AnchorPoint = Vector2.new(1, 1),
    BackgroundTransparency = 1,
}, Main)
New("UIStroke", {
    Color = Config.BorderColor, Transparency = 0.82, Thickness = 1,
}, PanelHost)
New("UICorner", { CornerRadius = UDim.new(0, 12) }, PanelHost)

-- ============================================================
--  各个大类面板
-- ============================================================

-- ---------- 抓包面板 ----------
local packetPage = New("ScrollingFrame", {
    Size = UDim2.new(1, -16, 1, -14),
    Position = UDim2.new(0, 8, 0, 7),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 2, 0),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, PanelHost)
packetPage.Visible = false

local function buildPacketPage()
    AutoSize(packetPage, 10)

    -- 实时请求日志
    local logBox, logContent = Section("实时请求日志", packetPage)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, logContent)
    local logLine = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 90),
        BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.5, BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 2, 0), ScrollBarThickness = 3,
    }, logContent)

    local function log(text, color)
        local line = New("TextLabel", {
            Text = os.date("%H:%M:%S ") .. text,
            Size = UDim2.new(1, -4, 0, 18),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            TextColor3 = color or Config.SubText,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, logLine)
    end
    log("工具加载完成", Config.Accent)
    log("等待捕获 Hit 请求…")

    -- 接口重发区
    local repBox, repContent = Section("接口重发(参数可改)", packetPage)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, repContent)

    local selBox = New("Frame", {
        Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 0,
    }, repContent)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, selBox)

    local methodLabel = New("TextLabel", {
        Text = "POST", Size = UDim2.new(0, 40, 0, 20), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextColor3 = Config.Accent, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, selBox)
    local urlBox = New("TextBox", {
        PlaceholderText = "接口地址…",
        Size = UDim2.new(1, 0, 0, 20), Text = "",
        Font = Enum.Font.Code, TextColor3 = Config.TextColor, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.4, BorderSizePixel = 0,
    }, selBox)
    New("UICorner", { CornerRadius = UDim.new(0, 5) }, urlBox)

    local bodyBox = New("TextBox", {
        PlaceholderText = "发送的 body(JSON)…",
        Size = UDim2.new(1, 0, 0, 46),
        Text = "", TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
        MultiLine = true,
        Font = Enum.Font.Code, TextColor3 = Config.TextColor, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.4, BorderSizePixel = 0,
    }, selBox)
    New("UICorner", { CornerRadius = UDim.new(0, 5) }, bodyBox)

    local sendBtn = TextBtn("发送请求", UDim2.new(0.35, 0, 0, 30), repContent, function()
        local ok, res = pcall(function()
            return Http:RequestAsync({
                Url = urlBox.Text,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = bodyBox.Text,
            })
        end)
        log("状态 " .. (ok and res.StatusCode or "失败") .. " " .. urlBox.Text,
            ok and Config.Accent or Color3.fromRGB(255, 120, 120))
    end)

    -- 从 PacketDB 一键填充
    local flow = New("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, repContent)
    New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, flow)
    for i, p in ipairs(PacketDB) do
        TextBtn(p.name .. " → 填入", UDim2.new(0, 120, 1, 0), flow, function()
            urlBox.Text = p.url
            bodyBox.Text = p.body
            methodLabel.Text = p.method
        end)
    end
end
buildPacketPage()

-- ---------- 设置面板 ----------
local settingPage = New("Frame", {
    Size = UDim2.new(1, -16, 1, -14),
    Position = UDim2.new(0, 8, 0, 7),
    BackgroundTransparency = 1,
}, PanelHost)
settingPage.Visible = false
do
    AutoSize(settingPage, 10)
    local top, content = Section("界面设置", settingPage)

    local row = New("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, content)
    New("TextLabel", {
        Text = "UI 透明度", Size = UDim2.new(0, 80, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        TextColor3 = Config.TextColor, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local slider = New("TextButton", {
        Text = "", Size = UDim2.new(1, -90, 0, 10),
        Position = UDim2.new(0, 84, 0.5, -5),
        BackgroundColor3 = Config.PanelBG, BackgroundTransparency = 0.3, BorderSizePixel = 0,
    }, row)
    New("UICorner", { CornerRadius = UDim.new(0, 5) }, slider)
    local fill = New("Frame", {
        Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = Config.Accent, BorderSizePixel = 0,
    }, slider)
    New("UICorner", { CornerRadius = UDim.new(0, 5) }, fill)
end

-- ============================================================
--  左侧按钮 & 切换
-- ============================================================
local function selectCat(id)
    currentCat = id
    for _, b in ipairs(sideBtns) do
        b.BackgroundTransparency = 0.85
        b.TextColor3 = Config.TextColor
    end
    local sel = sideBtns[id]
    if sel then
        sel.BackgroundTransparency = 0.4
        sel.TextColor3 = Config.Accent
    end
    packetPage.Visible = (id == "packet")
    settingPage.Visible = (id == "setting")
end

for _, cat in ipairs(Categories) do
    local b = TextBtn(cat.label, UDim2.new(1, 0, 0, 32), SideScroll, function()
        selectCat(cat.id)
    end)
    b.LayoutOrder = cat.order or 0
    sideBtns[cat.id] = b
end
selectCat(currentCat)

-- ============================================================
--  最小化 → 悬浮球
-- ============================================================
local Ball = New("TextButton", {
    Text = "★",
    Size = UDim2.new(0, 56, 0, 56),
    Position = UDim2.new(1, -74, 1, -74),
    AnchorPoint = Vector2.new(1, 1),
    Font = Enum.Font.GothamBold, TextColor3 = Config.TextColor, TextSize = 24,
    BackgroundColor3 = Config.GlassColor, BackgroundTransparency = Config.GlassTrans,
    AutoButtonColor = false, BorderSizePixel = 0,
}, sg)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, Ball)
New("UIStroke", { Color = Config.BorderColor, Transparency = Config.BorderTrans, Thickness = 1 }, Ball)
New("TextLabel", {
    Text = "展开", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4),
    Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1,
    Font = Enum.Font.Gotham, TextColor3 = Config.SubText, TextSize = 8,
}, Ball)
Ball.Visible = false

-- 悬浮球拖动
local ballDrag
Ball.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        ballDrag = i.Position
    end
end)
Ball.InputChanged:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseMovement and ballDrag then
        local delta = i.Position - ballDrag
        Ball.Position = UDim2.new(
            (Ball.Position.X.Scale), (Ball.Position.X.Offset + delta.X) ,
            (Ball.Position.Y.Scale), (Ball.Position.Y.Offset + delta.Y))
    end
end)
Ball.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then ballDrag = nil end
end)

MinBtn.Activated:Connect(function()
    Main.Visible = false
    Ball.Visible = true
end)
Ball.Activated:Connect(function()
    Ball.Visible = false
    Main.Visible = true
    Main:MakeJoints()
    -- 保持悬浮球逻辑, 仅为了兼容
end)
CloseBtn.Activated:Connect(function()
    sg:Destroy()
end)

-- ============================================================
--  抓包 Hook 占位 ── 把 rspy 拿到的请求挂到这里
-- ============================================================
-- 标准打法: 拦截游戏里发请求的 Remote 事件/函数, 把 URL/body 记录进日志。
-- 常见 Hook 点(视游戏而定, 拿到 rspy 包后定位替换):
--   hookmetamethod(game, "__namecall", ...)
--   newcclosure(...) 包 Remote:InvokeServer/FireServer
-- 这里给出一个通用模板:
--[[
local old
old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if getnamecallmethod(self) == "FireServer" and self:IsA("RemoteEvent") then
        local args = {...}
        -- 在这里用 rspy 解析出的字段做处理/转发
    end
    return old(self, ...)
end))
]]

-- 首轮提示(控制在台)
warn("[抓包工具] 已加载 — 请提交 rspy 数据替换 PacketDB 与 Hook 点")