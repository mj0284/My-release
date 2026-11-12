-- F5 Trainer - Cyberpunk 2077 트레이너 메뉴 (Cyber Engine Tweaks 모드)
--
-- 필요 모드: Cyber Engine Tweaks, RED4ext, Codeware
--   * CET      : Lua 실행 / ImGui 화면 / 게임 스크립트 호출
--   * Codeware : 게임의 원시 키 입력(F5, 방향키) 수신 -> 바인딩 설정 없이 바로 F5 로 열림
--
-- 조작
--   F5              메뉴 열기/닫기 (설정에서 변경 가능)
--   방향키 위/아래   항목 이동        (넘패드 8/2)
--   방향키 좌/우     값 조절/토글     (넘패드 4/6)
--   Enter           선택/실행        (넘패드 5)
--   Backspace       뒤로/닫기        (넘패드 0)
--   CET 오버레이가 열려 있을 때는 마우스 클릭으로 조작
local Util = require("modules/util")
local Config = require("modules/config")
local Lang = require("modules/lang")
local Input = require("modules/input")
local Cheats = require("modules/cheats")
local Menu = require("modules/menu")
local UI = require("modules/ui")

local F5Trainer = {
    version = "1.0.0",
    ready = false,
    overlayOpen = false,
}

local NAV_KEYS = {
    IK_Up = "up", IK_Down = "down", IK_Left = "left", IK_Right = "right",
    IK_Enter = "select", IK_Backspace = "back",
    IK_NumPad8 = "up", IK_NumPad2 = "down", IK_NumPad4 = "left", IK_NumPad6 = "right",
    IK_NumPad5 = "select", IK_NumPad0 = "back",
}

-- 꾹 누르면 반복되는 키 (이동/조절만. 선택/뒤로는 반복하지 않는다)
local REPEAT_KEYS = {
    IK_Up = true, IK_Down = true, IK_Left = true, IK_Right = true,
    IK_NumPad8 = true, IK_NumPad2 = true, IK_NumPad4 = true, IK_NumPad6 = true,
}

local QUICKSAVE_KEY = "IK_F5"   -- 게임 기본 퀵세이브 키
local QUICKSAVE_WINDOW = 0.35   -- 이 시간 안에 F5 눌림이 있었으면 트레이너용 입력으로 본다 (초)
local QUICKSAVE_DEFER = 0.15    -- F5 이벤트가 뒤늦게 올 수 있어 판단을 미루는 시간 (초)

local autoOpened = false        -- Codeware 없이 오버레이를 열어서 자동으로 띄운 경우
local pendingQuickSave = nil    -- { controller = 게임 UI 컨트롤러, at = 시각 }
local bypassQuickSave = false
local loggedErrors = {}

local function logOnce(tag, err)
    if not loggedErrors[tag] then
        loggedErrors[tag] = true
        Util.log(tag .. " error: " .. tostring(err))
    end
end

----------------------------------------------------------------------------------------------------
-- 키 입력
----------------------------------------------------------------------------------------------------

local function handleKey(key, pressed, isRepeat)
    if not pressed then
        return
    end
    if key == Config.data.toggleKey then
        if not isRepeat then
            Menu.toggle()
        end
        return
    end
    -- 오버레이가 열려 있으면 마우스로 조작한다 (어차피 키 입력이 게임까지 오지 않는다).
    if not Menu.visible or F5Trainer.overlayOpen then
        return
    end
    local dir = NAV_KEYS[key]
    if dir then
        Menu.navigate(dir)
    end
end

-- CET 키 바인딩(선택 사항). Codeware 가 없거나 다른 키 조합으로 열고 싶을 때
-- CET 오버레이 > Bindings 에서 키를 지정하면 된다. CET 핫키는 키를 뗄 때 실행된다.
registerHotkey("f5trainer_toggle", "F5 Trainer: open / close menu", function()
    if not F5Trainer.ready then
        return
    end
    -- 같은 키가 Codeware 쪽에서 이미 처리됐다면 두 번 토글하지 않는다.
    if Input.available and Input.pressedWithin(Config.data.toggleKey, 2.0) then
        return
    end
    Menu.toggle()
end)

----------------------------------------------------------------------------------------------------
-- F5 퀵세이브 충돌 처리
----------------------------------------------------------------------------------------------------
-- 게임 기본 퀵세이브 키가 F5 라서, 그대로 두면 메뉴를 열 때마다 퀵세이브가 된다.
-- 메뉴 키가 F5 이고 옵션이 켜져 있으면 F5 로 들어온 퀵세이브 요청만 걸러 낸다.
-- (퀵세이브를 다른 키로 바꿔 쓰는 경우에는 그대로 저장된다.)

local function guardQuickSave()
    return Input.available and Config.data.blockQuickSave and Config.data.toggleKey == QUICKSAVE_KEY
end

local function installQuickSaveGuard()
    Override("gameuiInGameMenuGameController", "HandleQuickSave", function(self, wrapped)
        if bypassQuickSave or not guardQuickSave() then
            wrapped()
            return
        end
        if Input.pressedWithin(QUICKSAVE_KEY, QUICKSAVE_WINDOW) then
            return -- 트레이너 키로 눌린 F5: 저장하지 않는다
        end
        -- 키 이벤트가 이 호출보다 늦게 도착하는 경우를 대비해 잠깐 보류했다가 onUpdate 에서 결정한다.
        pendingQuickSave = { controller = self, at = Util.now() }
    end)
end

local function updatePendingQuickSave()
    local pending = pendingQuickSave
    if not pending then
        return
    end
    local pressedAt = Input.lastPressTime(QUICKSAVE_KEY)
    if pressedAt and pressedAt >= pending.at - QUICKSAVE_WINDOW then
        pendingQuickSave = nil -- F5 눌림 확인: 버린다
    elseif Util.now() - pending.at >= QUICKSAVE_DEFER then
        pendingQuickSave = nil -- 다른 키로 요청된 퀵세이브: 원래대로 실행
        bypassQuickSave = true
        local ok, err = pcall(function() pending.controller:HandleQuickSave() end)
        bypassQuickSave = false
        if not ok then
            logOnce("deferred quick save", err)
        end
    end
end

----------------------------------------------------------------------------------------------------
-- CET 이벤트
----------------------------------------------------------------------------------------------------

registerForEvent("onInit", function()
    Config.load()
    Lang.set(Config.data.language)
    Menu.init()

    Input.handler = handleKey
    Input.repeatKeys = REPEAT_KEYS
    Input.init()

    local ok, err = pcall(installQuickSaveGuard)
    if not ok then
        Util.log("quick save guard not installed: " .. tostring(err))
    end

    -- 세이브를 불러와 플레이어가 다시 붙을 때마다 유지형 치트를 재적용한다.
    ok, err = pcall(function()
        Observe("PlayerPuppet", "OnGameAttached", function()
            Cheats.onSessionStart()
        end)
    end)
    if not ok then
        Util.log("session observer not installed: " .. tostring(err))
    end
    Cheats.onSessionStart() -- 게임 도중 모드를 리로드한 경우

    F5Trainer.ready = true
    Util.log(string.format("v%s loaded - menu key: %s%s", F5Trainer.version,
        Input.keyLabel(Config.data.toggleKey),
        Input.available and "" or " (Codeware missing: use the CET overlay or bind a CET hotkey)"))
end)

registerForEvent("onUpdate", function(deltaTime)
    if not F5Trainer.ready then
        return
    end
    local ok, err = pcall(Input.poll)
    if not ok then logOnce("input", err) end

    ok, err = pcall(updatePendingQuickSave)
    if not ok then logOnce("quick save guard", err) end

    ok, err = pcall(Cheats.update, deltaTime)
    if not ok then logOnce("update", err) end
end)

registerForEvent("onDraw", function()
    if not F5Trainer.ready then
        return
    end
    UI.draw(F5Trainer.overlayOpen)
end)

registerForEvent("onOverlayOpen", function()
    F5Trainer.overlayOpen = true
    Input.reset() -- 오버레이가 입력을 가로채서 키 떼는 이벤트를 놓치므로 눌림 상태를 비운다
    -- Codeware 가 없으면 키로 열 수 없으니 오버레이를 열 때 같이 띄운다.
    if F5Trainer.ready and not Input.available and not Menu.visible then
        Menu.open()
        autoOpened = true
    end
end)

registerForEvent("onOverlayClose", function()
    F5Trainer.overlayOpen = false
    Input.reset()
    if autoOpened then
        autoOpened = false
        Menu.close()
    end
end)

registerForEvent("onShutdown", function()
    pcall(Cheats.shutdown)
end)

return F5Trainer
