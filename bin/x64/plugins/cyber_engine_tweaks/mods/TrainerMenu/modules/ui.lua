-- 메뉴 화면 그리기 (ImGui)
--
-- CET 오버레이가 닫혀 있으면 ImGui 는 마우스/키보드 입력을 받지 못하므로 이 창은 "보여 주기"만 하고
-- 조작은 input.lua 가 받은 키로 한다. 오버레이가 열려 있으면 같은 창을 마우스로 클릭해서 쓴다.
local Util = require("modules/util")
local Lang = require("modules/lang")
local Config = require("modules/config")
local Input = require("modules/input")
local Cheats = require("modules/cheats")
local Menu = require("modules/menu")

local UI = {}

-- 색 (r, g, b, a)
local YELLOW = { 0.99, 0.93, 0.04, 1.00 }
local CYAN   = { 0.00, 0.94, 1.00, 1.00 }
local GREEN  = { 0.35, 1.00, 0.45, 1.00 }
local RED    = { 1.00, 0.35, 0.35, 1.00 }
local GREY   = { 0.62, 0.64, 0.68, 1.00 }
local WHITE  = { 0.95, 0.95, 0.95, 1.00 }

local STYLE_COLORS = 6
local STYLE_VARS = 2
local drawErrorLogged = false

local function text(color, str)
    ImGui.TextColored(color[1], color[2], color[3], color[4], str)
end

-- 자동 줄바꿈되는 색 글자. Push/Pop 사이에서 에러가 나도 스택이 어긋나지 않게 한다.
local function wrapped(color, str)
    ImGui.PushStyleColor(ImGuiCol.Text, color[1], color[2], color[3], color[4])
    pcall(ImGui.TextWrapped, str)
    ImGui.PopStyleColor(1)
end

local function windowFlags(overlayOpen)
    local F = ImGuiWindowFlags
    if overlayOpen then
        return Util.flags(F.NoTitleBar, F.NoResize, F.NoScrollbar, F.NoCollapse,
            F.AlwaysAutoResize, F.NoSavedSettings)
    end
    return Util.flags(F.NoTitleBar, F.NoResize, F.NoScrollbar, F.NoCollapse,
        F.AlwaysAutoResize, F.NoSavedSettings,
        F.NoMouseInputs, F.NoNavInputs, F.NoNavFocus, F.NoFocusOnAppearing)
end

local function drawHeader(overlayOpen, width)
    text(YELLOW, Lang.t("title"))
    local path = Menu.path()
    if path ~= "" then
        ImGui.SameLine()
        text(GREY, "> " .. path)
    end

    -- 오버레이에서는 키보드를 못 쓰니 뒤로/닫기 버튼을 둔다.
    if overlayOpen then
        local fontSize = ImGui.GetFontSize()
        ImGui.SameLine(width - fontSize * 3.6)
        if Menu.depth() > 1 then
            if ImGui.SmallButton(" < ##tm_back") then
                Menu.back()
            end
        else
            ImGui.Dummy(fontSize * 1.4, 1)
        end
        ImGui.SameLine()
        if ImGui.SmallButton(" X ##tm_close") then
            Menu.close()
        end
    end
    ImGui.Separator()
end

local function drawRows(overlayOpen, width)
    local menu = Menu.current()
    local cursor = Menu.cursor()
    local pad = ImGui.GetFontSize() * 0.6

    for index, item in ipairs(menu.items) do
        local label = Menu.labelOf(item)
        local value, isOn = Menu.valueOf(item)
        local selected = (index == cursor)

        if ImGui.Selectable(label .. "##tm_row" .. index, selected) and overlayOpen then
            Menu.setCursor(index)
            Menu.activate()
        end
        if overlayOpen and ImGui.IsItemClicked(1) then
            Menu.setCursor(index)
            Menu.adjust(-1)
        end

        if value ~= "" then
            if item.type == "choice" then
                value = "< " .. value .. " >"
            end
            local valueWidth = ImGui.CalcTextSize(value)
            ImGui.SameLine(width - valueWidth - pad)
            local color = WHITE
            if item.type == "toggle" then
                color = isOn and GREEN or GREY
            elseif item.type == "choice" then
                color = CYAN
            elseif item.type == "submenu" then
                color = YELLOW
            end
            text(color, value)
        end
    end
end

local function drawFooter(overlayOpen)
    ImGui.Separator()

    local status = Menu.activeStatus()
    if status then
        wrapped(status.ok and GREEN or RED, status.text)
    end

    if Cheats.getToggle("noclip") then
        wrapped(CYAN, Lang.t("hint_noclip"))
    end

    if overlayOpen then
        wrapped(GREY, Lang.t("hint_mouse"))
    elseif Input.available then
        wrapped(GREY, Lang.t("hint_keys"))
        wrapped(GREY, Lang.t("opened_with", Input.keyLabel(Config.data.toggleKey)))
    end

    if not Input.available then
        wrapped(RED, Lang.t("no_codeware"))
    end
end

local function drawBody(overlayOpen)
    local width = ImGui.GetWindowWidth()
    drawHeader(overlayOpen, width)
    drawRows(overlayOpen, width)
    drawFooter(overlayOpen)
end

-- onDraw 에서 매 프레임 호출
function UI.draw(overlayOpen)
    if not Menu.visible then
        return
    end

    local width = ImGui.GetFontSize() * 25
    local _, screenHeight = GetDisplayResolution()

    ImGui.SetNextWindowPos(60, 140, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSizeConstraints(width, 60, width, math.max(200, (screenHeight or 1080) - 160))
    ImGui.SetNextWindowBgAlpha(0.92)

    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.04, 0.05, 0.08, 1.00)
    ImGui.PushStyleColor(ImGuiCol.Border, YELLOW[1], YELLOW[2], YELLOW[3], 0.85)
    ImGui.PushStyleColor(ImGuiCol.Header, 0.00, 0.55, 0.65, 0.65)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.00, 0.65, 0.75, 0.80)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.00, 0.75, 0.85, 0.95)
    ImGui.PushStyleColor(ImGuiCol.Separator, YELLOW[1], YELLOW[2], YELLOW[3], 0.45)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 4.0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1.0)

    -- Begin 이 false 를 돌려줘도 End 는 반드시 호출해야 한다.
    if ImGui.Begin("Trainer Menu##trainermenu_main", windowFlags(overlayOpen)) then
        local ok, err = pcall(drawBody, overlayOpen)
        if not ok and not drawErrorLogged then
            drawErrorLogged = true
            Util.log("draw error: " .. tostring(err))
        end
    end
    ImGui.End()

    ImGui.PopStyleVar(STYLE_VARS)
    ImGui.PopStyleColor(STYLE_COLORS)
end

return UI
