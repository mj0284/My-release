-- 트레이너 기능 (게임 API 호출은 전부 여기에 모아 둔다)
--
-- 공개 함수는 모두 (ok, message) 를 돌려준다. message 는 메뉴 하단 상태줄에 표시된다.
-- 게임 함수 이름/시그니처는 게임 2.x 스크립트 덤프와 Appearance Menu Mod 소스를 보고 맞췄다.
local Util = require("modules/util")
local Lang = require("modules/lang")
local Config = require("modules/config")
local Input = require("modules/input")

local Cheats = {}

local SOURCE = "TrainerMenu"         -- 갓모드/경찰 잠금에 남기는 출처 이름
local LEGACY_SOURCE = "F5Trainer"    -- 모드 이름을 바꾸기 전에 쓰던 출처 이름 (세이브에 남아 있을 수 있다)
local DILATION_REASON = "consoleCommand"
local TICK_INTERVAL = 0.2            -- 유지형 치트(무적, 무한 스태미나 등) 갱신 주기 (초)
local AMMO_INTERVAL = 2.0            -- 예비 탄약 보충 확인 주기 (초)
local AMMO_LOW, AMMO_REFILL = 60, 200
local SESSION_SETTLE = 1.0           -- 세이브 로드 후 재적용까지 기다리는 시간 (초)
local MAX_LEVEL, MAX_STREET_CRED = 60, 50

local AMMO_TYPES = { "Ammo.HandgunAmmo", "Ammo.RifleAmmo", "Ammo.ShotgunAmmo", "Ammo.SniperRifleAmmo" }
local CRAFT_MATERIALS = {
    "Items.CommonMaterial1", "Items.UncommonMaterial1", "Items.RareMaterial1",
    "Items.EpicMaterial1", "Items.LegendaryMaterial1",
}
local HACK_MATERIALS = {
    "Items.QuickHackUncommonMaterial1", "Items.QuickHackRareMaterial1",
    "Items.QuickHackEpicMaterial1", "Items.QuickHackLegendaryMaterial1",
}

local toggles = {
    god = false, stamina = false, ram = false, oxygen = false,
    ammo = false, carry = false, noclip = false, noPolice = false,
}
local speedMult = 1.0
local gameSpeed = 1.0

local statMods = {}        -- [slot] = 추가해 둔 스탯 모디파이어 핸들 (제거할 때 필요)
local noclipPos = nil      -- 노클립 중 우리가 관리하는 위치 { x, y, z }
local tickTimer, ammoTimer = 0, 0
local sessionDirtyAt = nil -- 세션(세이브 로드) 시작 시각. 설정돼 있으면 재적용 대기 중
local preGame = { value = false, at = -100 }
local loggedErrors = {}

----------------------------------------------------------------------------------------------------
-- 내부 헬퍼
----------------------------------------------------------------------------------------------------

local function shortError(err)
    local text = tostring(err):gsub("^.-:%d+: ", "")
    if #text > 90 then
        text = text:sub(1, 90) .. "..."
    end
    return text
end

-- 매 틱 반복되는 호출이 실패하면 로그가 도배되므로 종류별로 한 번만 남긴다.
local function logOnce(tag, err)
    if not loggedErrors[tag] then
        loggedErrors[tag] = true
        Util.log(tag .. " failed: " .. tostring(err))
    end
end

local function guarded(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        logOnce(tag, err)
    end
    return ok
end

-- 메인 메뉴에도 "플레이어"가 붙어 있을 수 있어서 프리게임 여부를 따로 확인한다 (1초 캐시).
local function isPreGame()
    local t = Util.now()
    if t - preGame.at < 1.0 then
        return preGame.value
    end
    local ok, res = pcall(function()
        return GetSingleton("inkMenuScenario"):GetSystemRequestsHandler():IsPreGame()
    end)
    preGame.value = ok and res == true
    preGame.at = t
    return preGame.value
end

local function rawPlayer()
    local ok, player = pcall(function()
        local p = Game.GetPlayer()
        if p and p:IsAttached() then
            return p
        end
        return nil
    end)
    if ok then
        return player
    end
    return nil
end

-- 게임 플레이 중일 때만 플레이어를 돌려준다.
function Cheats.getPlayer()
    local player = rawPlayer()
    if player and not isPreGame() then
        return player
    end
    return nil
end

-- fn(player) 실행. fn 은 성공 메시지(또는 nil)를 돌려주거나, 실패 시 false, 메시지를 돌려준다.
local function withPlayer(fn)
    local player = Cheats.getPlayer()
    if not player then
        return false, Lang.t("not_in_game")
    end
    local ok, a, b = pcall(fn, player)
    if not ok then
        Util.log("error: " .. tostring(a))
        return false, Lang.t("failed", shortError(a))
    end
    if a == false then
        return false, b
    end
    return true, a
end

local function devSystem()
    return Game.GetScriptableSystemsContainer():Get("PlayerDevelopmentSystem")
end

local function fillPool(player, poolName)
    Game.GetStatPoolsSystem():RequestSettingStatPoolMaxValue(
        player:GetEntityID(), gamedataStatPoolType[poolName], player)
end

-- 스탯 모디파이어를 slot 이름으로 관리한다. 기존 것이 있으면 지우고, active 면 새로 붙인다.
local function applyStatMod(player, slot, active, statName, modTypeName, value)
    local stats = Game.GetStatsSystem()
    local id = player:GetEntityID()
    if statMods[slot] then
        local old = statMods[slot]
        statMods[slot] = nil
        pcall(function() stats:RemoveModifier(id, old) end)
    end
    if active then
        local mod = RPGManager.CreateStatModifier(
            gamedataStatType[statName], gameStatModifierType[modTypeName], value)
        stats:AddModifier(id, mod)
        statMods[slot] = mod
    end
end

local function applySpeed(player)
    applyStatMod(player, "speed", speedMult ~= 1.0, "MaxSpeed", "Multiplier", speedMult)
end

local function applyCarry(player)
    applyStatMod(player, "carry", toggles.carry, "CarryCapacity", "Additive", 100000.0)
end

local function applyGameSpeed()
    local timeSystem = Game.GetTimeSystem()
    if gameSpeed == 1.0 then
        timeSystem:UnsetTimeDilation(DILATION_REASON)
    else
        timeSystem:SetTimeDilation(DILATION_REASON, gameSpeed)
    end
end

-- 경찰(프리벤션) 시스템 켜기/끄기 요청. 게임은 출처 이름별 잠금 목록으로 관리한다:
--   isActive=false -> 우리 이름을 잠금 목록에 추가하고 시스템을 끈다 (이미 목록에 있으면 아무 일도 안 함)
--   isActive=true  -> 우리 이름을 목록에서 빼고, 목록이 비면 시스템을 켠다
local function sendPolice(active, source)
    local request = TogglePreventionSystem.new()
    request.sourceName = CName.new(source or SOURCE)
    request.isActive = active
    Game.GetScriptableSystemsContainer():Get("PreventionSystem"):QueueRequest(request)
end

-- 잠금이 목록에 남아 있어도 게임이 시스템을 다시 켜 버리는 경우가 있다 (수배 단계 변경 요청 등).
-- 그래서 끌 때는 "빼고 -> 다시 넣기"로 보내서 항상 꺼진 상태가 되게 한다.
local function setPoliceDisabled(disabled)
    sendPolice(true)
    if disabled then
        sendPolice(false)
    end
end

local function removeGodMode(player)
    Game.GetGodModeSystem():RemoveGodMode(
        player:GetEntityID(), gameGodModeType.Invulnerable, CName.new(SOURCE))
end

local function removeAmmoFlag(player)
    -- 차량 전투 중에는 게임이 스스로 이 플래그를 쓰고 있으므로 건드리지 않는다.
    local ok, gameOwned = pcall(function()
        return StatusEffectSystem.ObjectHasStatusEffectWithTag(player, "InfiniteAmmo")
    end)
    if ok and gameOwned == true then
        return
    end
    Game.GetInventoryManager():RemoveEquipmentStateFlag(gameEEquipmentManagerState.InfiniteAmmo)
end

local function gameSeconds(timeSystem)
    local gameTime = timeSystem:GetGameTime()
    local ok, seconds = pcall(function() return gameTime:GetSeconds(gameTime) end)
    if ok and type(seconds) == "number" then
        return seconds
    end
    return GameTime.GetSeconds(gameTime)
end

----------------------------------------------------------------------------------------------------
-- 토글 (켜짐/꺼짐)
----------------------------------------------------------------------------------------------------

-- 토글을 바꿀 때 한 번 실행되는 처리. 유지 자체는 Cheats.update 가 한다.
local onToggle = {
    god = function(on, player)
        if not on then removeGodMode(player) end
    end,
    ammo = function(on, player)
        if not on then removeAmmoFlag(player) end
    end,
    carry = function(_, player)
        applyCarry(player)
    end,
    noclip = function()
        noclipPos = nil
    end,
    noPolice = function(on)
        setPoliceDisabled(on)
    end,
}

function Cheats.getToggle(name)
    return toggles[name] == true
end

function Cheats.setToggle(name, on)
    if toggles[name] == nil then
        return false, "unknown toggle: " .. tostring(name)
    end
    on = on and true or false

    if name == "noclip" and on and not Input.available then
        return false, Lang.t("need_codeware")
    end

    local player = Cheats.getPlayer()
    if not player then
        if on then
            return false, Lang.t("not_in_game")
        end
        toggles[name] = false -- 게임 밖에서 끄는 것은 그냥 허용
        return true
    end

    local previous = toggles[name]
    toggles[name] = on
    local handler = onToggle[name]
    if handler then
        local ok, err = pcall(handler, on, player)
        if not ok then
            toggles[name] = previous
            Util.log("toggle " .. name .. " error: " .. tostring(err))
            return false, Lang.t("failed", shortError(err))
        end
    end
    tickTimer = TICK_INTERVAL -- 다음 프레임에 바로 반영
    return true
end

----------------------------------------------------------------------------------------------------
-- 플레이어
----------------------------------------------------------------------------------------------------

function Cheats.heal()
    return withPlayer(function(player)
        fillPool(player, "Health")
        fillPool(player, "Stamina")
        fillPool(player, "Memory")
        return Lang.t("done", Lang.t("heal"))
    end)
end

function Cheats.getSpeedMult()
    return speedMult
end

function Cheats.setSpeedMult(value)
    value = Util.clamp(Util.round(value, 2), 0.5, 5.0)
    return withPlayer(function(player)
        local previous = speedMult
        speedMult = value
        local ok, err = pcall(applySpeed, player)
        if not ok then
            speedMult = previous
            error(err, 0)
        end
    end)
end

function Cheats.getNoclipSpeed()
    return Config.data.noclipSpeed
end

function Cheats.setNoclipSpeed(value)
    Config.data.noclipSpeed = Util.clamp(math.floor(value + 0.5), 1, 100)
    Config.save()
    return true
end

----------------------------------------------------------------------------------------------------
-- 돈 / 성장 / 아이템
----------------------------------------------------------------------------------------------------

function Cheats.addMoney(amount)
    return withPlayer(function()
        Game.AddToInventory("Items.money", amount)
        return Lang.t("done", "+" .. Util.comma(amount))
    end)
end

local function giveAll(list, quantity, labelKey)
    return withPlayer(function()
        for _, item in ipairs(list) do
            Game.AddToInventory(item, quantity)
        end
        return Lang.t("done", Lang.t(labelKey))
    end)
end

function Cheats.giveAmmo()
    return giveAll(AMMO_TYPES, 500, "give_ammo")
end

function Cheats.giveCraftMaterials()
    return giveAll(CRAFT_MATERIALS, 200, "give_mats")
end

function Cheats.giveHackMaterials()
    return giveAll(HACK_MATERIALS, 100, "give_hackmats")
end

-- 현재 레벨과 상한. 상한은 게임에 물어본다 (팬텀 리버티가 없으면 레벨 상한이 50).
-- 조회가 실패하면 스탯 값과 알려진 상한으로 대신한다.
local function proficiencyInfo(player, profName, statName, fallbackMax)
    local profType = gamedataProficiencyType[profName]
    local ok, current, maxLevel = pcall(function()
        local system = devSystem()
        return system:GetProficiencyLevel(player, profType),
            system:GetProficiencyAbsoluteMaxLevel(player, profType)
    end)
    if ok and type(current) == "number" and type(maxLevel) == "number" and maxLevel > 0 then
        return current, maxLevel
    end
    current = Game.GetStatsSystem():GetStatValue(player:GetEntityID(), gamedataStatType[statName])
    return math.floor(current + 0.5), fallbackMax
end

local function raiseProficiency(profName, statName, amount, fallbackMax, messageKey)
    return withPlayer(function(player)
        local current, maxLevel = proficiencyInfo(player, profName, statName, fallbackMax)
        if current >= maxLevel then
            return false, Lang.t("max_reached", maxLevel)
        end
        local target = math.min(current + amount, maxLevel)
        local request = SetProficiencyLevel.new()
        request:Set(player, target, gamedataProficiencyType[profName], telemetryLevelGainReason.Gameplay)
        devSystem():QueueRequest(request)
        return Lang.t(messageKey, target)
    end)
end

function Cheats.addLevel(amount)
    return raiseProficiency("Level", "Level", amount, MAX_LEVEL, "level_now")
end

function Cheats.addStreetCred(amount)
    return raiseProficiency("StreetCred", "StreetCred", amount, MAX_STREET_CRED, "cred_now")
end

-- kind: "Attribute"(특성) | "Primary"(퍽) | "Espionage"(렐릭)
function Cheats.addDevPoints(kind, amount, labelKey)
    return withPlayer(function(player)
        local request = AddDevelopmentPoints.new()
        request:Set(player, amount, gamedataDevelopmentPointType[kind])
        devSystem():QueueRequest(request)
        return Lang.t("done", Lang.t(labelKey))
    end)
end

----------------------------------------------------------------------------------------------------
-- 월드
----------------------------------------------------------------------------------------------------

-- 시간을 hour 시 정각으로. 과거로 되돌리지 않고 항상 다음에 오는 그 시각으로 넘긴다.
function Cheats.setHour(hour)
    return withPlayer(function()
        local timeSystem = Game.GetTimeSystem()
        local total = gameSeconds(timeSystem)
        local target = total - (total % 86400) + hour * 3600
        if target <= total then
            target = target + 86400
        end
        timeSystem:SetGameTimeBySeconds(target)
        return Lang.t("time_set", hour, 0)
    end)
end

function Cheats.addHours(hours)
    return withPlayer(function()
        local timeSystem = Game.GetTimeSystem()
        local target = gameSeconds(timeSystem) + hours * 3600
        timeSystem:SetGameTimeBySeconds(target)
        local ofDay = target % 86400
        return Lang.t("time_set", math.floor(ofDay / 3600), math.floor((ofDay % 3600) / 60))
    end)
end

function Cheats.getGameSpeed()
    return gameSpeed
end

function Cheats.setGameSpeed(value)
    return withPlayer(function()
        local previous = gameSpeed
        gameSpeed = value
        local ok, err = pcall(applyGameSpeed)
        if not ok then
            gameSpeed = previous
            error(err, 0)
        end
    end)
end

function Cheats.clearWanted()
    return withPlayer(function()
        local request = SetWantedLevel.new()
        request.m_wantedLevel = EPreventionHeatStage.Heat_0
        Game.GetScriptableSystemsContainer():Get("PreventionSystem"):QueueRequest(request)
        -- 이 요청을 처리하면서 게임이 경찰 시스템을 다시 켠다. 비활성화 중이면 바로 다시 끈다.
        if toggles.noPolice then
            setPoliceDisabled(true)
        end
        return Lang.t("wanted_cleared")
    end)
end

----------------------------------------------------------------------------------------------------
-- 텔레포트
----------------------------------------------------------------------------------------------------

local function teleport(player, x, y, z, yaw)
    Game.GetTeleportationFacility():Teleport(
        player, Vector4.new(x, y, z, 1.0), EulerAngles.new(0.0, 0.0, yaw or player:GetWorldYaw()))
    if noclipPos then
        noclipPos = { x = x, y = y, z = z }
    end
end

-- 지도에서 추적 중인 핀(직접 찍은 핀 포함) 위치로 이동
function Cheats.teleportToWaypoint()
    return withPlayer(function(player)
        local mappinSystem = Game.GetMappinSystem()
        local mappin = mappinSystem:GetMappin(mappinSystem:GetManuallyTrackedMappinID())
        if not mappin then
            return false, Lang.t("no_waypoint")
        end
        local pos = mappin:GetWorldPosition()
        teleport(player, pos.x, pos.y, pos.z + 1.0)
        return Lang.t("teleported")
    end)
end

function Cheats.getSavedPosition(slot)
    return Config.data.positions[tostring(slot)]
end

function Cheats.savePosition(slot)
    return withPlayer(function(player)
        local pos = player:GetWorldPosition()
        Config.data.positions[tostring(slot)] = {
            x = Util.round(pos.x, 2), y = Util.round(pos.y, 2), z = Util.round(pos.z, 2),
            yaw = Util.round(player:GetWorldYaw(), 1),
        }
        Config.save()
        return Lang.t("saved_slot", slot)
    end)
end

function Cheats.loadPosition(slot)
    local saved = Cheats.getSavedPosition(slot)
    if not saved then
        return false, Lang.t("slot_empty", slot)
    end
    return withPlayer(function(player)
        teleport(player, saved.x, saved.y, saved.z, saved.yaw)
        return Lang.t("teleported")
    end)
end

----------------------------------------------------------------------------------------------------
-- 매 프레임 갱신
----------------------------------------------------------------------------------------------------

local function axis(positive, negative)
    return (positive and 1 or 0) - (negative and 1 or 0)
end

-- 노클립: 매 프레임 우리가 계산한 위치로 텔레포트해서 중력/충돌을 무시한다.
local function updateNoclip(player, dt)
    if not noclipPos then
        local pos = player:GetWorldPosition()
        noclipPos = { x = pos.x, y = pos.y, z = pos.z }
    end

    local forward = axis(Input.isDown("IK_W"), Input.isDown("IK_S"))
    local side = axis(Input.isDown("IK_D"), Input.isDown("IK_A"))
    local up = axis(Input.isDown("IK_Space"),
        Input.isDown("IK_LControl") or Input.isDown("IK_Ctrl") or Input.isDown("IK_C"))

    if forward ~= 0 or side ~= 0 or up ~= 0 then
        local camera = Game.GetCameraSystem()
        local f = camera:GetActiveCameraForward()
        local r = camera:GetActiveCameraRight()
        local speed = Config.data.noclipSpeed
        if Input.isDown("IK_LShift") or Input.isDown("IK_Shift") then
            speed = speed * 4
        end
        local step = speed * math.min(dt, 0.1)
        noclipPos.x = noclipPos.x + (f.x * forward + r.x * side) * step
        noclipPos.y = noclipPos.y + (f.y * forward + r.y * side) * step
        noclipPos.z = noclipPos.z + (f.z * forward + r.z * side + up) * step
    end

    Game.GetTeleportationFacility():Teleport(
        player, Vector4.new(noclipPos.x, noclipPos.y, noclipPos.z, 1.0),
        EulerAngles.new(0.0, 0.0, player:GetWorldYaw()))
end

-- 유지형 치트: 게임이 값을 되돌려 놓을 수 있으므로 주기적으로 다시 적용한다.
local function maintain(player)
    local id = player:GetEntityID()

    if toggles.god then
        guarded("god mode", function()
            local godMode = Game.GetGodModeSystem()
            if not godMode:HasGodMode(id, gameGodModeType.Invulnerable) then
                godMode:AddGodMode(id, gameGodModeType.Invulnerable, CName.new(SOURCE))
            end
        end)
        guarded("health refill", fillPool, player, "Health")
    end
    if toggles.stamina then
        guarded("stamina refill", fillPool, player, "Stamina")
    end
    if toggles.ram then
        guarded("ram refill", fillPool, player, "Memory")
    end
    if toggles.oxygen then
        guarded("oxygen refill", fillPool, player, "Oxygen")
    end
    if toggles.ammo then
        guarded("infinite ammo flag", function()
            local inventory = Game.GetInventoryManager()
            local flag = gameEEquipmentManagerState.InfiniteAmmo
            if not inventory:HasEquipmentStateFlag(flag) then
                inventory:AddEquipmentStateFlag(flag)
            end
        end)
    end
end

-- 무한 탄약 보조: 예비 탄약이 바닥나기 전에 채워 둔다.
local function topUpAmmo(player)
    local transactions = Game.GetTransactionSystem()
    for _, ammo in ipairs(AMMO_TYPES) do
        local itemID = ItemID.FromTDBID(TweakDBID.new(ammo))
        if transactions:GetItemQuantity(player, itemID) < AMMO_LOW then
            Game.AddToInventory(ammo, AMMO_REFILL)
        end
    end
end

-- 세이브를 불러오면 붙여 둔 모디파이어/시간 배속/경찰 잠금이 사라지거나 어긋나므로 다시 맞춘다.
local function reapplyAfterSessionStart(player)
    noclipPos = nil
    -- 예전 핸들을 그냥 버리면, 같은 세션에서 다시 불렸을 때 모디파이어가 이중으로 붙는다.
    -- apply 함수가 "기존 것 제거 -> 필요하면 새로 추가"를 하므로 항상 그쪽으로 맡긴다.
    guarded("reapply speed", applySpeed, player)
    guarded("reapply carry", applyCarry, player)
    if gameSpeed ~= 1.0 then
        guarded("reapply game speed", applyGameSpeed)
    end
    -- 예전 이름(F5Trainer)으로 경찰을 끈 채 저장한 세이브라면 그 잠금이 남아 있다. 풀 방법이 없어지므로 치워 준다.
    guarded("clear legacy police lock", sendPolice, true, LEGACY_SOURCE)
    -- 꺼져 있으면 이전 세션에서 세이브에 남았을 수 있는 잠금을 지우고, 켜져 있으면 다시 건다.
    guarded("reapply police", setPoliceDisabled, toggles.noPolice)
end

-- PlayerPuppet 이 게임에 붙을 때(세이브 로드 등) init.lua 의 옵저버가 호출한다.
function Cheats.onSessionStart()
    sessionDirtyAt = Util.now()
end

-- onUpdate 에서 매 프레임 호출
function Cheats.update(dt)
    local player = nil

    if toggles.noclip then
        player = rawPlayer()
        if player then
            guarded("noclip", updateNoclip, player, dt)
        else
            noclipPos = nil
        end
    end

    tickTimer = tickTimer + dt
    if tickTimer < TICK_INTERVAL then
        return
    end
    local elapsed = tickTimer
    tickTimer = 0

    player = Cheats.getPlayer()
    if not player then
        return
    end

    if sessionDirtyAt and (Util.now() - sessionDirtyAt) >= SESSION_SETTLE then
        sessionDirtyAt = nil
        reapplyAfterSessionStart(player)
    end

    maintain(player)

    if toggles.ammo then
        ammoTimer = ammoTimer + elapsed
        if ammoTimer >= AMMO_INTERVAL then
            ammoTimer = 0
            guarded("ammo top-up", topUpAmmo, player)
        end
    end
end

-- 모드 리로드/종료 시 게임에 남겨 둔 것들을 가능한 만큼 되돌린다.
function Cheats.shutdown()
    local player = rawPlayer()
    if not player then
        return
    end
    if toggles.god then pcall(removeGodMode, player) end
    if toggles.ammo then pcall(removeAmmoFlag, player) end
    if toggles.noPolice then pcall(setPoliceDisabled, false) end
    toggles.carry = false
    pcall(applyCarry, player)
    if speedMult ~= 1.0 then
        speedMult = 1.0
        pcall(applySpeed, player)
    end
    if gameSpeed ~= 1.0 then
        gameSpeed = 1.0
        pcall(applyGameSpeed)
    end
    for name in pairs(toggles) do
        toggles[name] = false
    end
end

return Cheats
