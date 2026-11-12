-- 메뉴 모델과 조작 (화면 그리기는 ui.lua)
--
-- 항목 종류
--   submenu : 하위 메뉴로 들어감            { type, label, items }
--   toggle  : 켜짐/꺼짐                     { type, label, get(), set(bool) }
--   action  : 한 번 실행                    { type, label, run() }
--   choice  : 여러 값 중 하나 (좌우로 변경)  { type, label, options, get(), set(value), format(value) }
--
-- label 은 문자열(Lang 키) 또는 화면에 그릴 때마다 호출되는 함수.
-- set/run 은 (ok, message) 를 돌려주고, message 는 상태줄에 잠깐 표시된다.
local Util = require("modules/util")
local Lang = require("modules/lang")
local Config = require("modules/config")
local Input = require("modules/input")
local Cheats = require("modules/cheats")

local Menu = {
    visible = false,
    status = nil, -- { text = string, ok = boolean, at = number }
}

local STATUS_SECONDS = 3.5

local root = nil
local stack = {} -- { { menu = submenu, cursor = index }, ... }

----------------------------------------------------------------------------------------------------
-- 메뉴 정의
----------------------------------------------------------------------------------------------------

local function toggle(labelKey, name)
    return {
        type = "toggle", label = labelKey,
        get = function() return Cheats.getToggle(name) end,
        set = function(value) return Cheats.setToggle(name, value) end,
    }
end

local function action(labelKey, run)
    return { type = "action", label = labelKey, run = run }
end

local function onOffText(value)
    return Lang.t(value and "on" or "off")
end

local function buildTeleportItems()
    local items = { action("tp_waypoint", Cheats.teleportToWaypoint) }
    for slot = 1, Config.SAVE_SLOTS do
        items[#items + 1] = {
            type = "action",
            label = function()
                local saved = Cheats.getSavedPosition(slot)
                local text = Lang.t("tp_load", slot)
                if saved then
                    return string.format("%s  (%.0f, %.0f, %.0f)", text, saved.x, saved.y, saved.z)
                end
                return text .. "  " .. Lang.t("tp_empty")
            end,
            run = function() return Cheats.loadPosition(slot) end,
        }
    end
    for slot = 1, Config.SAVE_SLOTS do
        items[#items + 1] = {
            type = "action",
            label = function() return Lang.t("tp_save", slot) end,
            run = function() return Cheats.savePosition(slot) end,
        }
    end
    return items
end

local function build()
    return {
        type = "submenu", label = "title",
        items = {
            {
                type = "submenu", label = "menu_player",
                items = {
                    toggle("god", "god"),
                    toggle("inf_stamina", "stamina"),
                    toggle("inf_ram", "ram"),
                    toggle("inf_oxygen", "oxygen"),
                    toggle("inf_ammo", "ammo"),
                    toggle("carry", "carry"),
                    action("heal", Cheats.heal),
                    {
                        type = "choice", label = "speed",
                        options = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0 },
                        get = Cheats.getSpeedMult, set = Cheats.setSpeedMult,
                        format = function(v) return string.format("x%.1f", v) end,
                    },
                    toggle("noclip", "noclip"),
                    {
                        type = "choice", label = "noclip_speed",
                        options = { 2, 5, 10, 20, 40, 80 },
                        get = Cheats.getNoclipSpeed, set = Cheats.setNoclipSpeed,
                        format = function(v) return string.format("%d m/s", v) end,
                    },
                },
            },
            {
                type = "submenu", label = "menu_progress",
                items = {
                    action("money_10k", function() return Cheats.addMoney(10000) end),
                    action("money_100k", function() return Cheats.addMoney(100000) end),
                    action("money_1m", function() return Cheats.addMoney(1000000) end),
                    action("level_up1", function() return Cheats.addLevel(1) end),
                    action("level_up5", function() return Cheats.addLevel(5) end),
                    action("cred_up1", function() return Cheats.addStreetCred(1) end),
                    action("cred_up5", function() return Cheats.addStreetCred(5) end),
                    action("attr_1", function() return Cheats.addDevPoints("Attribute", 1, "attr_1") end),
                    action("attr_5", function() return Cheats.addDevPoints("Attribute", 5, "attr_5") end),
                    action("perk_1", function() return Cheats.addDevPoints("Primary", 1, "perk_1") end),
                    action("perk_5", function() return Cheats.addDevPoints("Primary", 5, "perk_5") end),
                    action("relic_1", function() return Cheats.addDevPoints("Espionage", 1, "relic_1") end),
                },
            },
            {
                type = "submenu", label = "menu_items",
                items = {
                    action("give_ammo", Cheats.giveAmmo),
                    action("give_mats", Cheats.giveCraftMaterials),
                    action("give_hackmats", Cheats.giveHackMaterials),
                },
            },
            {
                type = "submenu", label = "menu_world",
                items = {
                    action("time_morning", function() return Cheats.setHour(8) end),
                    action("time_noon", function() return Cheats.setHour(12) end),
                    action("time_evening", function() return Cheats.setHour(19) end),
                    action("time_midnight", function() return Cheats.setHour(0) end),
                    action("time_plus1", function() return Cheats.addHours(1) end),
                    {
                        type = "choice", label = "game_speed",
                        options = { 0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0 },
                        get = Cheats.getGameSpeed, set = Cheats.setGameSpeed,
                        format = function(v) return string.format("x%.2f", v) end,
                    },
                    action("clear_wanted", Cheats.clearWanted),
                    toggle("no_police", "noPolice"),
                },
            },
            {
                type = "submenu", label = "menu_teleport",
                items = buildTeleportItems(),
            },
            {
                type = "submenu", label = "menu_settings",
                items = {
                    {
                        type = "choice", label = "language",
                        options = { "ko", "en" },
                        get = function() return Config.data.language end,
                        set = function(value)
                            Config.data.language = value
                            Lang.set(value)
                            Config.save()
                            return true
                        end,
                        format = function(v) return v == "ko" and "Korean" or "English" end,
                    },
                    {
                        type = "choice", label = "toggle_key",
                        options = Config.TOGGLE_KEYS,
                        get = function() return Config.data.toggleKey end,
                        set = function(value)
                            Config.data.toggleKey = value
                            Config.save()
                            return true
                        end,
                        format = Input.keyLabel,
                    },
                    {
                        type = "toggle", label = "block_quicksave",
                        get = function() return Config.data.blockQuickSave end,
                        set = function(value)
                            Config.data.blockQuickSave = value and true or false
                            Config.save()
                            return true
                        end,
                    },
                },
            },
        },
    }
end

----------------------------------------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------------------------------------

function Menu.init()
    root = build()
    stack = { { menu = root, cursor = 1 } }
    Menu.visible = false
    Menu.status = nil
end

local function top()
    return stack[#stack]
end

function Menu.current()
    return top().menu
end

function Menu.cursor()
    return top().cursor
end

function Menu.depth()
    return #stack
end

-- "플레이어 > ..." 형태의 현재 경로
function Menu.path()
    local parts = {}
    for i = 2, #stack do
        parts[#parts + 1] = Menu.labelOf(stack[i].menu)
    end
    return table.concat(parts, " > ")
end

function Menu.labelOf(item)
    if type(item.label) == "function" then
        local ok, text = pcall(item.label)
        return ok and tostring(text) or "?"
    end
    return Lang.t(item.label)
end

-- 항목 오른쪽에 표시할 값 문자열과 켜짐 여부(toggle 만)
function Menu.valueOf(item)
    if item.type == "toggle" then
        local ok, value = pcall(item.get)
        value = ok and value == true
        return onOffText(value), value
    elseif item.type == "choice" then
        local ok, value = pcall(item.get)
        if not ok then
            return "?", nil
        end
        local fmtOk, text = pcall(item.format or tostring, value)
        return fmtOk and tostring(text) or tostring(value), nil
    elseif item.type == "submenu" then
        return ">", nil
    end
    return "", nil
end

function Menu.setStatus(ok, text)
    if text and text ~= "" then
        Menu.status = { text = text, ok = ok and true or false, at = Util.now() }
    end
end

-- 표시 시간이 지난 상태 메시지는 nil
function Menu.activeStatus()
    local status = Menu.status
    if status and (Util.now() - status.at) <= STATUS_SECONDS then
        return status
    end
    return nil
end

----------------------------------------------------------------------------------------------------
-- 조작
----------------------------------------------------------------------------------------------------

function Menu.open()
    Menu.visible = true
end

function Menu.close()
    Menu.visible = false
end

function Menu.toggle()
    Menu.visible = not Menu.visible
end

function Menu.setCursor(index)
    local items = top().menu.items
    if index >= 1 and index <= #items then
        top().cursor = index
    end
end

local function moveCursor(delta)
    local entry = top()
    local count = #entry.menu.items
    if count == 0 then
        return
    end
    entry.cursor = ((entry.cursor - 1 + delta) % count) + 1
end

-- set/run 실행 결과를 상태줄에 반영
local function report(ok, message)
    if ok == false and (message == nil or message == "") then
        message = Lang.t("failed", "?")
    end
    Menu.setStatus(ok ~= false, message)
end

local function callItem(fn, ...)
    local callOk, ok, message = pcall(fn, ...)
    if not callOk then
        Util.log("menu item error: " .. tostring(ok))
        report(false, Lang.t("failed", tostring(ok)))
        return
    end
    report(ok, message)
end

local function indexOf(options, value)
    local best, bestDiff = 1, math.huge
    for i, option in ipairs(options) do
        if option == value then
            return i
        end
        if type(option) == "number" and type(value) == "number" then
            local diff = math.abs(option - value)
            if diff < bestDiff then
                best, bestDiff = i, diff
            end
        end
    end
    return best
end

-- choice 값을 delta 만큼 이동. wrap 이 true 면 끝에서 처음으로 돈다(Enter 로 넘길 때).
local function stepChoice(item, delta, wrap)
    local ok, value = pcall(item.get)
    if not ok then
        return
    end
    local count = #item.options
    local index = indexOf(item.options, value) + delta
    if wrap then
        index = ((index - 1) % count) + 1
    else
        index = Util.clamp(index, 1, count)
    end
    local newValue = item.options[index]
    if newValue ~= value then
        callItem(item.set, newValue)
    end
end

local function flipToggle(item)
    local ok, value = pcall(item.get)
    callItem(item.set, not (ok and value == true))
end

function Menu.back()
    if #stack > 1 then
        stack[#stack] = nil
    else
        Menu.close()
    end
end

-- 현재 커서 항목 실행 (Enter / 마우스 클릭)
function Menu.activate()
    local entry = top()
    local item = entry.menu.items[entry.cursor]
    if not item then
        return
    end
    if item.type == "submenu" then
        stack[#stack + 1] = { menu = item, cursor = 1 }
    elseif item.type == "toggle" then
        flipToggle(item)
    elseif item.type == "action" then
        callItem(item.run)
    elseif item.type == "choice" then
        stepChoice(item, 1, true)
    end
end

-- 좌/우: 값 조절. delta 는 -1 또는 +1.
function Menu.adjust(delta)
    local entry = top()
    local item = entry.menu.items[entry.cursor]
    if not item then
        return
    end
    if item.type == "choice" then
        stepChoice(item, delta, false)
    elseif item.type == "toggle" then
        flipToggle(item)
    elseif item.type == "submenu" and delta > 0 then
        Menu.activate()
    end
end

-- dir: "up" | "down" | "left" | "right" | "select" | "back"
function Menu.navigate(dir)
    if dir == "up" then
        moveCursor(-1)
    elseif dir == "down" then
        moveCursor(1)
    elseif dir == "left" then
        Menu.adjust(-1)
    elseif dir == "right" then
        Menu.adjust(1)
    elseif dir == "select" then
        Menu.activate()
    elseif dir == "back" then
        Menu.back()
    end
end

return Menu
