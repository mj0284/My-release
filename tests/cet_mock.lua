-- 테스트용 가짜 CET / 게임 환경
--
-- 실제 게임 없이 모드를 돌려 보기 위한 것. 일부러 "엄격하게" 만들었다:
--   * 여기 정의되지 않은 함수/열거형 멤버/전역을 쓰면 에러 -> 이름 오타를 잡는다.
--   * 인자 타입/순서를 실제 시그니처대로 검사한다.
-- 등록된 이름과 시그니처는 CET 소스(sol_imgui.h, Scripting.cpp), Codeware 소스,
-- 게임 2.x 스크립트 덤프에서 직접 확인한 것만 넣었다.
local Mock = {}

-- 모드용 require 로 바꿔 끼우기 전의 진짜 require
local realRequire = require

local function strict(typeName, members)
    return setmetatable(members, {
        __index = function(_, key)
            error(string.format("mock: %s has no member '%s'", typeName, tostring(key)), 2)
        end,
    })
end

local function enum(typeName, names)
    local members = {}
    for _, name in ipairs(names) do
        members[name] = setmetatable({ value = name, enum = typeName }, {
            __tostring = function() return typeName .. "." .. name end,
        })
    end
    return strict(typeName, members)
end

local function expectEnum(value, typeName, what)
    if type(value) ~= "table" or value.enum ~= typeName then
        error(string.format("mock: %s expects %s, got %s", what, typeName, tostring(value)), 3)
    end
end

local function expectNumber(value, what)
    if type(value) ~= "number" then
        error(string.format("mock: %s expects number, got %s", what, type(value)), 3)
    end
end

-- CET 는 CName 인자에 Lua 문자열을 넣어도 자동 변환해 준다.
local function cnameText(value, what)
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" and value.cname then
        return value.cname
    end
    error(string.format("mock: %s expects CName or string, got %s", what, tostring(value)), 3)
end

local KNOWN_EVENTS = {
    onHook = true, onTweak = true, onInit = true, onShutdown = true,
    onUpdate = true, onDraw = true, onOverlayOpen = true, onOverlayClose = true,
}

-- opts: { codeware = bool, modRoot = string, dataDir = string }
function Mock.install(opts)
    opts = opts or {}

    local world = {
        codeware = opts.codeware ~= false,
        clock = 100.0,
        events = {}, hotkeys = {}, overrides = {}, observers = {},
        keyCallbacks = {},
        log = {},
        -- 게임 상태
        hasPlayer = true, attached = true, preGame = false,
        pos = { x = 10.0, y = 20.0, z = 30.0 }, yaw = 90.0,
        cameraForward = { x = 0.0, y = 1.0, z = 0.0 }, cameraRight = { x = 1.0, y = 0.0, z = 0.0 },
        godModes = {}, equipFlags = {}, statMods = {}, pools = {},
        stats = { Level = 20, StreetCred = 10 },
        maxLevels = { Level = 60, StreetCred = 50 },
        brokenProficiencyQuery = false,
        inventory = {},
        time = 3 * 86400 + 10 * 3600 + 30 * 60, -- 3일째 10:30
        dilation = {},
        policeLocks = {}, policeEnabled = true,
        requests = {},
        mappin = nil,
        teleports = 0,
        gameOwnsInfiniteAmmo = false,
        quickSaves = 0,
        -- ImGui 상태
        ui = { texts = {}, rows = {}, begins = 0, colors = 0, vars = 0, frames = 0 },
        click = nil, rightClick = nil, clickButton = nil,
    }

    local function record(name, ...)
        world.log[#world.log + 1] = { name = name, args = { ... } }
    end

    function world.count(name)
        local n = 0
        for _, entry in ipairs(world.log) do
            if entry.name == name then
                n = n + 1
            end
        end
        return n
    end

    function world.clearLog()
        world.log = {}
    end

    local playerID = setmetatable({ entityID = 1 }, { __tostring = function() return "EntityID(player)" end })

    local function expectPlayerID(value, what)
        if value ~= playerID then
            error("mock: " .. what .. " expects the player's EntityID", 3)
        end
    end

    ------------------------------------------------------------------------------------------------
    -- 기본 타입
    ------------------------------------------------------------------------------------------------
    local CName = strict("CName", {
        new = function(text)
            assert(type(text) == "string", "CName.new expects a string")
            return { cname = text }
        end,
    })
    local Vector4 = strict("Vector4", {
        new = function(x, y, z, w)
            expectNumber(x, "Vector4.x") expectNumber(y, "Vector4.y") expectNumber(z, "Vector4.z")
            return { x = x, y = y, z = z, w = w or 0 }
        end,
    })
    local EulerAngles = strict("EulerAngles", {
        new = function(roll, pitch, yaw)
            expectNumber(roll, "roll") expectNumber(pitch, "pitch") expectNumber(yaw, "yaw")
            return { roll = roll, pitch = pitch, yaw = yaw }
        end,
    })
    local TweakDBID = strict("TweakDBID", {
        new = function(name)
            assert(type(name) == "string")
            return { tdbid = name }
        end,
    })
    local ItemID = strict("ItemID", {
        FromTDBID = function(tdbid)
            assert(type(tdbid) == "table" and tdbid.tdbid, "ItemID.FromTDBID expects TweakDBID")
            return { item = tdbid.tdbid }
        end,
    })

    ------------------------------------------------------------------------------------------------
    -- 플레이어 / 게임 시스템
    ------------------------------------------------------------------------------------------------
    local player
    player = strict("PlayerPuppet", {
        IsAttached = function(self) assert(self == player) return world.attached end,
        GetEntityID = function(self) assert(self == player) return playerID end,
        GetWorldPosition = function(self)
            assert(self == player)
            return { x = world.pos.x, y = world.pos.y, z = world.pos.z, w = 1.0 }
        end,
        GetWorldYaw = function(self) assert(self == player) return world.yaw end,
    })
    world.player = player

    local godModeSystem = strict("GodModeSystem", {
        HasGodMode = function(_, id, gmType)
            expectPlayerID(id, "HasGodMode") expectEnum(gmType, "gameGodModeType", "HasGodMode")
            for key in pairs(world.godModes) do
                if key:match("^" .. gmType.value .. "|") then return true end
            end
            return false
        end,
        AddGodMode = function(_, id, gmType, source)
            expectPlayerID(id, "AddGodMode") expectEnum(gmType, "gameGodModeType", "AddGodMode")
            world.godModes[gmType.value .. "|" .. cnameText(source, "AddGodMode source")] = true
            record("AddGodMode", gmType.value)
            return true
        end,
        RemoveGodMode = function(_, id, gmType, source)
            expectPlayerID(id, "RemoveGodMode") expectEnum(gmType, "gameGodModeType", "RemoveGodMode")
            world.godModes[gmType.value .. "|" .. cnameText(source, "RemoveGodMode source")] = nil
            record("RemoveGodMode", gmType.value)
            return true
        end,
    })

    local statPoolsSystem = strict("StatPoolsSystem", {
        RequestSettingStatPoolMaxValue = function(_, id, poolType, instigator)
            expectPlayerID(id, "RequestSettingStatPoolMaxValue")
            expectEnum(poolType, "gamedataStatPoolType", "RequestSettingStatPoolMaxValue")
            assert(instigator == nil or instigator == player, "instigator must be a GameObject")
            world.pools[poolType.value] = (world.pools[poolType.value] or 0) + 1
            record("FillPool", poolType.value)
        end,
    })

    local statsSystem = strict("StatsSystem", {
        GetStatValue = function(_, id, statType)
            expectPlayerID(id, "GetStatValue") expectEnum(statType, "gamedataStatType", "GetStatValue")
            return world.stats[statType.value] or 0
        end,
        AddModifier = function(_, id, modifier)
            expectPlayerID(id, "AddModifier")
            assert(type(modifier) == "table" and modifier.isStatModifier, "AddModifier expects gameStatModifierData")
            world.statMods[#world.statMods + 1] = modifier
            record("AddModifier", modifier.stat, modifier.kind, modifier.value)
            return true
        end,
        RemoveModifier = function(_, id, modifier)
            expectPlayerID(id, "RemoveModifier")
            for i, existing in ipairs(world.statMods) do
                if existing == modifier then
                    table.remove(world.statMods, i)
                    record("RemoveModifier", modifier.stat)
                    return true
                end
            end
            return false
        end,
    })

    local inventoryManager = strict("InventoryManager", {
        HasEquipmentStateFlag = function(_, flag)
            expectEnum(flag, "gameEEquipmentManagerState", "HasEquipmentStateFlag")
            return world.equipFlags[flag.value] == true
        end,
        AddEquipmentStateFlag = function(_, flag)
            expectEnum(flag, "gameEEquipmentManagerState", "AddEquipmentStateFlag")
            world.equipFlags[flag.value] = true
            record("AddEquipFlag", flag.value)
        end,
        RemoveEquipmentStateFlag = function(_, flag)
            expectEnum(flag, "gameEEquipmentManagerState", "RemoveEquipmentStateFlag")
            world.equipFlags[flag.value] = nil
            record("RemoveEquipFlag", flag.value)
        end,
    })

    local transactionSystem = strict("TransactionSystem", {
        GetItemQuantity = function(_, obj, itemID)
            assert(obj == player, "GetItemQuantity expects a GameObject")
            assert(type(itemID) == "table" and itemID.item, "GetItemQuantity expects ItemID")
            return world.inventory[itemID.item] or 0
        end,
    })

    local function gameTimeObject()
        local gameTime
        gameTime = strict("GameTime", {
            -- 정적 함수라서 CET 에서는 gameTime:GetSeconds(gameTime) 형태로 부른다.
            GetSeconds = function(_, self)
                assert(self == gameTime, "GameTime.GetSeconds expects the GameTime as argument")
                return world.time
            end,
        })
        return gameTime
    end

    local timeSystem = strict("TimeSystem", {
        GetGameTime = function() return gameTimeObject() end,
        SetGameTimeBySeconds = function(_, seconds)
            expectNumber(seconds, "SetGameTimeBySeconds")
            assert(seconds == math.floor(seconds), "SetGameTimeBySeconds expects an integer")
            world.time = seconds
            record("SetGameTimeBySeconds", seconds)
        end,
        SetTimeDilation = function(_, reason, dilation)
            expectNumber(dilation, "SetTimeDilation")
            world.dilation[cnameText(reason, "SetTimeDilation reason")] = dilation
            record("SetTimeDilation", dilation)
        end,
        UnsetTimeDilation = function(_, reason)
            world.dilation[cnameText(reason, "UnsetTimeDilation reason")] = nil
            record("UnsetTimeDilation")
        end,
    })

    local teleportationFacility = strict("TeleportationFacility", {
        Teleport = function(_, obj, position, orientation)
            assert(obj == player, "Teleport expects a GameObject")
            expectNumber(position.x, "Teleport position") expectNumber(orientation.yaw, "Teleport yaw")
            world.pos = { x = position.x, y = position.y, z = position.z }
            world.yaw = orientation.yaw
            world.teleports = world.teleports + 1
            record("Teleport", position.x, position.y, position.z, orientation.yaw)
        end,
    })

    local mappinSystem = strict("MappinSystem", {
        GetManuallyTrackedMappinID = function() return { mappinID = world.mappin and 7 or 0 } end,
        GetMappin = function(_, id)
            assert(type(id) == "table" and id.mappinID, "GetMappin expects NewMappinID")
            if not world.mappin then return nil end
            local pos = world.mappin
            return strict("IMappin", {
                GetWorldPosition = function() return { x = pos.x, y = pos.y, z = pos.z, w = 1.0 } end,
            })
        end,
    })

    local cameraSystem = strict("CameraSystem", {
        GetActiveCameraForward = function() return world.cameraForward end,
        GetActiveCameraRight = function() return world.cameraRight end,
    })

    -- 요청을 받으면 게임 스크립트가 하는 일을 흉내 내서 world 상태에 반영한다.
    local function scriptableSystem(name)
        local members = {}
        if name == "PlayerDevelopmentSystem" then
            members.GetProficiencyLevel = function(_, owner, profType)
                assert(owner == player, "GetProficiencyLevel owner must be the player")
                expectEnum(profType, "gamedataProficiencyType", "GetProficiencyLevel")
                if world.brokenProficiencyQuery then error("query unavailable") end
                return world.stats[profType.value]
            end
            members.GetProficiencyAbsoluteMaxLevel = function(_, owner, profType)
                assert(owner == player, "GetProficiencyAbsoluteMaxLevel owner must be the player")
                expectEnum(profType, "gamedataProficiencyType", "GetProficiencyAbsoluteMaxLevel")
                if world.brokenProficiencyQuery then error("query unavailable") end
                return world.maxLevels[profType.value]
            end
        end
        members.QueueRequest = function(_, request)
                assert(type(request) == "table" and request.class, "QueueRequest expects a request object")
                world.requests[#world.requests + 1] = { system = name, request = request }
                record("Request:" .. request.class)
                if request.class == "SetProficiencyLevel" then
                    assert(name == "PlayerDevelopmentSystem")
                    world.stats[request.proficiency.value] = request.level
                elseif request.class == "AddDevelopmentPoints" then
                    assert(name == "PlayerDevelopmentSystem")
                    local kind = request.pointType.value
                    world.stats["DevPoints_" .. kind] = (world.stats["DevPoints_" .. kind] or 0) + request.amount
                elseif request.class == "TogglePreventionSystem" then
                    assert(name == "PreventionSystem")
                    -- PreventionSystem.OnTogglePreventionSystem 과 같은 규칙
                    local source = cnameText(request.sourceName, "sourceName")
                    assert(type(request.isActive) == "boolean", "isActive must be set")
                    if request.isActive then
                        if world.policeLocks[source] then
                            world.policeLocks[source] = nil
                            if next(world.policeLocks) == nil then
                                world.policeEnabled = true
                            end
                        end
                    elseif not world.policeLocks[source] then
                        world.policeLocks[source] = true
                        world.policeEnabled = false
                    end
                elseif request.class == "SetWantedLevel" then
                    -- PreventionSystem.OnSetWantedLevel: 잠금 목록과 상관없이 시스템을 켠다
                    assert(name == "PreventionSystem")
                    expectEnum(request.m_wantedLevel, "EPreventionHeatStage", "m_wantedLevel")
                    world.policeEnabled = true
                    world.wantedLevel = request.m_wantedLevel.value
                end
        end
        return strict(name, members)
    end
    local systems = {
        PlayerDevelopmentSystem = scriptableSystem("PlayerDevelopmentSystem"),
        PreventionSystem = scriptableSystem("PreventionSystem"),
    }
    local systemsContainer = strict("ScriptableSystemsContainer", {
        Get = function(_, name)
            local system = systems[cnameText(name, "ScriptableSystemsContainer.Get")]
            assert(system, "unknown scriptable system " .. tostring(name))
            return system
        end,
    })

    -- Codeware
    local callbackSystem = strict("CallbackSystem", {
        RegisterCallback = function(_, eventName, target, functionName, sticky)
            assert(cnameText(eventName, "event") == "Input/Key", "only Input/Key is mocked")
            assert(type(target) == "table" and target.spec, "target must come from NewProxy():Target()")
            assert(target.spec[functionName], "proxy has no function " .. tostring(functionName))
            assert(sticky == nil or type(sticky) == "boolean")
            world.keyCallbacks[#world.keyCallbacks + 1] = target.spec[functionName]
            record("RegisterCallback", "Input/Key")
        end,
    })

    local Game = strict("Game", {
        GetPlayer = function()
            if world.hasPlayer then return player end
            return nil
        end,
        GetCallbackSystem = function()
            if not world.codeware then
                error("Function GetCallbackSystem is not a GameInstance member and is not a global.")
            end
            return callbackSystem
        end,
        GetGodModeSystem = function() return godModeSystem end,
        GetStatPoolsSystem = function() return statPoolsSystem end,
        GetStatsSystem = function() return statsSystem end,
        GetInventoryManager = function() return inventoryManager end,
        GetTransactionSystem = function() return transactionSystem end,
        GetTimeSystem = function() return timeSystem end,
        GetTeleportationFacility = function() return teleportationFacility end,
        GetMappinSystem = function() return mappinSystem end,
        GetCameraSystem = function() return cameraSystem end,
        GetScriptableSystemsContainer = function() return systemsContainer end,
        AddToInventory = function(item, quantity)
            assert(type(item) == "string", "AddToInventory expects item path string")
            expectNumber(quantity, "AddToInventory quantity")
            world.inventory[item] = (world.inventory[item] or 0) + quantity
            record("AddToInventory", item, quantity)
        end,
    })

    ------------------------------------------------------------------------------------------------
    -- 스크립트 클래스
    ------------------------------------------------------------------------------------------------
    -- 필드를 직접 대입하는 요청 객체: 모르는 필드에 대입하면 에러
    local function fieldObject(class, fields)
        local allowed = {}
        for _, field in ipairs(fields) do allowed[field] = true end
        return setmetatable({ class = class }, {
            __newindex = function(self, key, value)
                if not allowed[key] then
                    error(string.format("mock: %s has no property '%s'", class, tostring(key)), 2)
                end
                rawset(self, key, value)
            end,
        })
    end

    local classes = {
        SetProficiencyLevel = strict("SetProficiencyLevel", {
            new = function()
                return {
                    class = "SetProficiencyLevel",
                    Set = function(self, owner, level, profType, reason)
                        assert(owner == player, "Set owner must be the player")
                        expectNumber(level, "level")
                        expectEnum(profType, "gamedataProficiencyType", "SetProficiencyLevel.Set")
                        expectEnum(reason, "telemetryLevelGainReason", "SetProficiencyLevel.Set")
                        self.level, self.proficiency, self.reason = level, profType, reason
                    end,
                }
            end,
        }),
        AddDevelopmentPoints = strict("AddDevelopmentPoints", {
            new = function()
                return {
                    class = "AddDevelopmentPoints",
                    Set = function(self, owner, amount, pointType)
                        assert(owner == player, "Set owner must be the player")
                        expectNumber(amount, "amount")
                        expectEnum(pointType, "gamedataDevelopmentPointType", "AddDevelopmentPoints.Set")
                        self.amount, self.pointType = amount, pointType
                    end,
                }
            end,
        }),
        SetWantedLevel = strict("SetWantedLevel", {
            new = function()
                return fieldObject("SetWantedLevel", { "m_wantedLevel", "m_forceGreyStars", "m_resetGreyStars" })
            end,
        }),
        TogglePreventionSystem = strict("TogglePreventionSystem", {
            new = function() return fieldObject("TogglePreventionSystem", { "sourceName", "isActive" }) end,
        }),
        RPGManager = strict("RPGManager", {
            CreateStatModifier = function(statType, modType, value)
                expectEnum(statType, "gamedataStatType", "CreateStatModifier")
                expectEnum(modType, "gameStatModifierType", "CreateStatModifier")
                expectNumber(value, "CreateStatModifier value")
                return { isStatModifier = true, stat = statType.value, kind = modType.value, value = value }
            end,
        }),
        StatusEffectSystem = strict("StatusEffectSystem", {
            ObjectHasStatusEffectWithTag = function(target, tag)
                assert(target == player)
                return cnameText(tag, "tag") == "InfiniteAmmo" and world.gameOwnsInfiniteAmmo
            end,
        }),
        GameTime = strict("GameTime", {
            GetSeconds = function() return world.time end,
        }),
    }

    local enums = {
        gameGodModeType = enum("gameGodModeType", { "Invulnerable", "Immortal", "Mortal" }),
        gamedataStatPoolType = enum("gamedataStatPoolType", { "Health", "Stamina", "Memory", "Oxygen" }),
        gamedataStatType = enum("gamedataStatType", { "MaxSpeed", "CarryCapacity", "Level", "StreetCred" }),
        gameStatModifierType = enum("gameStatModifierType", { "Additive", "AdditiveMultiplier", "Multiplier" }),
        gameEEquipmentManagerState = enum("gameEEquipmentManagerState", { "InfiniteAmmo" }),
        gamedataProficiencyType = enum("gamedataProficiencyType", { "Level", "StreetCred" }),
        gamedataDevelopmentPointType = enum("gamedataDevelopmentPointType",
            { "Attribute", "Espionage", "Primary", "Secondary" }),
        telemetryLevelGainReason = enum("telemetryLevelGainReason", { "Ignore", "Gameplay", "IsDebug" }),
        EPreventionHeatStage = enum("EPreventionHeatStage",
            { "Heat_0", "Heat_1", "Heat_2", "Heat_3", "Heat_4", "Heat_5" }),
    }

    ------------------------------------------------------------------------------------------------
    -- ImGui
    ------------------------------------------------------------------------------------------------
    local ui = world.ui
    local function labelOf(text)
        return (text:gsub("##.*$", ""))
    end

    local ImGui = strict("ImGui", {
        GetFontSize = function() return 18.0 end,
        GetWindowWidth = function() return 450.0 end,
        CalcTextSize = function(text)
            assert(type(text) == "string")
            return #text * 8.0, 18.0
        end,
        SetNextWindowPos = function(x, y, cond) expectNumber(x, "x") expectNumber(y, "y") expectNumber(cond, "cond") end,
        SetNextWindowSizeConstraints = function(a, b, c, d)
            expectNumber(a, "minX") expectNumber(b, "minY") expectNumber(c, "maxX") expectNumber(d, "maxY")
        end,
        SetNextWindowBgAlpha = function(alpha) expectNumber(alpha, "alpha") end,
        Begin = function(name, flags)
            assert(type(name) == "string") expectNumber(flags, "flags")
            ui.begins = ui.begins + 1
            ui.lastFlags = flags
            return true
        end,
        End = function()
            ui.begins = ui.begins - 1
            assert(ui.begins >= 0, "ImGui.End without Begin")
        end,
        PushStyleColor = function(idx, r, g, b, a)
            expectNumber(idx, "col") expectNumber(r, "r") expectNumber(g, "g") expectNumber(b, "b") expectNumber(a, "a")
            ui.colors = ui.colors + 1
        end,
        PopStyleColor = function(count)
            ui.colors = ui.colors - (count or 1)
            assert(ui.colors >= 0, "PopStyleColor underflow")
        end,
        PushStyleVar = function(idx, value)
            expectNumber(idx, "var") expectNumber(value, "value")
            ui.vars = ui.vars + 1
        end,
        PopStyleVar = function(count)
            ui.vars = ui.vars - (count or 1)
            assert(ui.vars >= 0, "PopStyleVar underflow")
        end,
        TextColored = function(r, g, b, a, text)
            expectNumber(r, "r") expectNumber(a, "a") assert(type(text) == "string")
            ui.texts[#ui.texts + 1] = text
        end,
        TextWrapped = function(text)
            assert(type(text) == "string")
            ui.texts[#ui.texts + 1] = text
        end,
        SameLine = function(offset) assert(offset == nil or type(offset) == "number") end,
        Dummy = function(w, h) expectNumber(w, "w") expectNumber(h, "h") end,
        Separator = function() end,
        Selectable = function(label, selected)
            assert(type(label) == "string") assert(type(selected) == "boolean")
            local text = labelOf(label)
            ui.rows[#ui.rows + 1] = { label = text, selected = selected }
            ui.lastItem = text
            if world.click == text then
                world.click = nil
                return true
            end
            return false
        end,
        IsItemClicked = function(button)
            if button == 1 and world.rightClick and world.rightClick == ui.lastItem then
                world.rightClick = nil
                return true
            end
            return false
        end,
        SmallButton = function(label)
            assert(type(label) == "string")
            local text = labelOf(label):gsub("^%s+", ""):gsub("%s+$", "")
            if world.clickButton == text then
                world.clickButton = nil
                return true
            end
            return false
        end,
    })

    local function flagTable(typeName, names)
        local t = {}
        for i, name in ipairs(names) do t[name] = 2 ^ (i - 1) end
        return strict(typeName, t)
    end

    ------------------------------------------------------------------------------------------------
    -- 전역 설치
    ------------------------------------------------------------------------------------------------
    local globals = {
        Game = Game, ImGui = ImGui,
        CName = CName, Vector4 = Vector4, EulerAngles = EulerAngles, TweakDBID = TweakDBID, ItemID = ItemID,
        ImGuiWindowFlags = flagTable("ImGuiWindowFlags", {
            "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "NoScrollWithMouse", "NoCollapse",
            "AlwaysAutoResize", "NoBackground", "NoSavedSettings", "NoMouseInputs", "MenuBar",
            "HorizontalScrollbar", "NoFocusOnAppearing", "NoBringToFrontOnFocus", "NoNavInputs", "NoNavFocus",
        }),
        ImGuiCol = strict("ImGuiCol", {
            Text = 0, WindowBg = 2, Border = 5, Header = 24, HeaderHovered = 25, HeaderActive = 26, Separator = 27,
        }),
        ImGuiCond = strict("ImGuiCond", { Always = 1, Once = 2, FirstUseEver = 4, Appearing = 8 }),
        ImGuiStyleVar = strict("ImGuiStyleVar", { WindowRounding = 3, WindowBorderSize = 4 }),
        GetDisplayResolution = function() return 1920.0, 1080.0 end,
        GetSingleton = function(name)
            assert(name == "inkMenuScenario", "only inkMenuScenario is mocked")
            return strict("inkMenuScenario", {
                GetSystemRequestsHandler = function()
                    return strict("inkISystemRequestsHandler", {
                        IsPreGame = function() return world.preGame end,
                    })
                end,
            })
        end,
        NewProxy = function(spec)
            assert(type(spec) == "table", "NewProxy expects a table")
            for name, entry in pairs(spec) do
                assert(type(entry.callback) == "function", "proxy function needs a callback")
                assert(type(entry.args) == "table", "proxy function needs args")
                if name == "OnKeyInput" then
                    assert(entry.args[1] == "handle:KeyInputEvent", "wrong arg type for OnKeyInput")
                end
            end
            local proxy
            proxy = strict("NativeProxy", {
                spec = spec,
                Target = function(self) assert(self == proxy) return proxy end,
                Function = function(self, name)
                    assert(self == proxy)
                    assert(spec[name], "proxy has no function " .. tostring(name))
                    return name
                end,
            })
            return proxy
        end,
        registerForEvent = function(name, callback)
            assert(KNOWN_EVENTS[name], "unknown CET event " .. tostring(name))
            assert(type(callback) == "function")
            world.events[name] = callback
        end,
        registerHotkey = function(id, description, callback)
            assert(type(id) == "string" and id:match("^[%w_%.]+$"), "invalid hotkey id")
            assert(type(description) == "string" and description ~= "", "hotkey needs a display name")
            assert(type(callback) == "function")
            assert(not world.hotkeys[id], "duplicate hotkey id")
            world.hotkeys[id] = callback
        end,
        Observe = function(class, method, callback)
            assert(type(class) == "string" and type(method) == "string" and type(callback) == "function")
            world.observers[class .. "." .. method] = callback
        end,
        Override = function(class, method, callback)
            assert(type(class) == "string" and type(method) == "string" and type(callback) == "function")
            world.overrides[class .. "." .. method] = callback
        end,
        spdlog = { info = function() end, error = function() end },
        bit32 = { bor = realRequire("bit").bor },
        json = dofile(opts.jsonPath),
    }
    for name, value in pairs(classes) do globals[name] = value end
    for name, value in pairs(enums) do globals[name] = value end
    for name, value in pairs(globals) do rawset(_G, name, value) end

    -- CET 샌드박스처럼 모드 폴더 기준으로 require / io.open 이 동작하게 한다.
    local modules = {}
    rawset(_G, "require", function(path)
        if modules[path] ~= nil then
            return modules[path]
        end
        local file = opts.modRoot .. "/" .. path
        if not file:match("%.lua$") then file = file .. ".lua" end
        local chunk = assert(loadfile(file))
        local result = chunk()
        modules[path] = result == nil and true or result
        return modules[path]
    end)

    local realOpen = io.open
    world.realOpen = realOpen
    rawset(io, "open", function(path, mode)
        assert(not path:match("^/") and not path:match("%.%."), "mod must stay inside its own folder: " .. path)
        return realOpen(opts.dataDir .. "/" .. path, mode or "r")
    end)

    local realClock = os.clock
    rawset(os, "clock", function() return world.clock end)

    local realPrint = print
    world.printed = {}
    rawset(_G, "print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        world.printed[#world.printed + 1] = table.concat(parts, " ")
    end)

    function world.uninstall()
        rawset(io, "open", realOpen)
        rawset(os, "clock", realClock)
        rawset(_G, "print", realPrint)
        rawset(_G, "require", realRequire)
        for name in pairs(globals) do rawset(_G, name, nil) end
    end

    ------------------------------------------------------------------------------------------------
    -- 테스트에서 쓰는 조작 함수
    ------------------------------------------------------------------------------------------------

    -- Codeware 가 보내는 키 이벤트
    function world.key(key, action)
        local event = strict("KeyInputEvent", {
            GetKey = function() return { value = key } end,
            GetAction = function() return { value = action } end,
        })
        for _, entry in ipairs(world.keyCallbacks) do
            entry.callback(event)
        end
    end

    -- 한 프레임 진행: onUpdate -> onDraw. ImGui 스택이 맞는지 매번 확인한다.
    function world.frame(dt)
        dt = dt or 0.016
        world.clock = world.clock + dt
        if world.events.onUpdate then world.events.onUpdate(dt) end
        ui.texts, ui.rows = {}, {}
        if world.events.onDraw then world.events.onDraw() end
        ui.frames = ui.frames + 1
        assert(ui.begins == 0, "ImGui Begin/End mismatch")
        assert(ui.colors == 0, "ImGui PushStyleColor/PopStyleColor mismatch")
        assert(ui.vars == 0, "ImGui PushStyleVar/PopStyleVar mismatch")
    end

    function world.frames(count, dt)
        for _ = 1, count do world.frame(dt) end
    end

    -- 키를 눌렀다 떼고 한 프레임 진행
    function world.tap(key)
        world.key(key, "IACT_Press")
        world.frame()
        world.key(key, "IACT_Release")
        world.frame()
    end

    function world.loadMod()
        local result = assert(loadfile(opts.modRoot .. "/init.lua"))()
        if world.events.onInit then world.events.onInit() end
        return result
    end

    -- 게임의 gameuiInGameMenuGameController: CET Override 가 걸린 HandleQuickSave 를 흉내 낸다.
    function world.quickSaveController()
        local controller
        controller = strict("gameuiInGameMenuGameController", {
            HandleQuickSave = function(self)
                assert(self == controller)
                local wrapped = function() world.quickSaves = world.quickSaves + 1 end
                local override = world.overrides["gameuiInGameMenuGameController.HandleQuickSave"]
                if override then
                    override(controller, wrapped)
                else
                    wrapped()
                end
            end,
        })
        return controller
    end

    function world.hasText(fragment)
        for _, text in ipairs(ui.texts) do
            if text:find(fragment, 1, true) then return true end
        end
        return false
    end

    function world.hasRow(fragment)
        for _, row in ipairs(ui.rows) do
            if row.label:find(fragment, 1, true) then return true end
        end
        return false
    end

    function world.rowLabels()
        local labels = {}
        for _, row in ipairs(ui.rows) do labels[#labels + 1] = row.label end
        return labels
    end

    function world.selectedRow()
        for index, row in ipairs(ui.rows) do
            if row.selected then return index, row.label end
        end
        return nil
    end

    return world
end

return Mock
