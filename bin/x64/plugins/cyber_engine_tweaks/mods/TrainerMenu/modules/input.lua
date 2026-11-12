-- 키 입력 처리
--
-- CET 는 오버레이가 닫혀 있으면 ImGui 에 키 입력을 넘기지 않고, registerHotkey 는 사용자가
-- 직접 키를 바인딩해야 한다. 그래서 "설치만 하면 바로 열리는" 동작은 Codeware 의
-- Input/Key 콜백(게임의 원시 키 입력)으로 구현한다.
--
-- 콜백은 게임 입력 처리 도중에 불리므로 여기서는 상태만 기록하고,
-- 실제 처리는 onUpdate 에서 Input.poll() 이 큐를 비우면서 한다.
local Util = require("modules/util")

local Input = {
    available = false,  -- Codeware 연결 성공 여부
    error = nil,        -- 실패했을 때의 에러 문자열
    handler = nil,      -- function(key, pressed, isRepeat)
    repeatKeys = {},    -- 꾹 누르면 반복 입력되는 키: [key] = true
}

local REPEAT_DELAY = 0.40     -- 반복 시작까지 (초)
local REPEAT_INTERVAL = 0.07  -- 반복 간격 (초)
local STUCK_TIMEOUT = 8.0     -- 떼는 이벤트를 놓친 경우를 대비한 반복 중단 시간 (초)
local MAX_QUEUE = 64
local MAX_ERRORS = 5

local down = {}        -- [key] = true (현재 눌려 있음)
local heldSince = {}   -- [key] = 처음 눌린 시각
local pressedAt = {}   -- [key] = 마지막 Press 이벤트 시각
local lastRepeat = {}  -- [key] = 마지막 반복 발생 시각
local queue = {}
local listener = nil   -- NewProxy 객체. 모듈 수준에서 잡고 있어야 GC 되지 않는다.
local errorCount = 0

local function push(key, pressed)
    if #queue >= MAX_QUEUE then
        table.remove(queue, 1)
    end
    queue[#queue + 1] = { key, pressed }
end

local function onKeyEvent(evt)
    local key = evt:GetKey().value
    local action = evt:GetAction().value
    if action == "IACT_Press" then
        local t = Util.now()
        pressedAt[key] = t
        if not down[key] then
            down[key] = true
            heldSince[key] = t
            lastRepeat[key] = nil
            push(key, true)
        end
    elseif action == "IACT_Release" then
        if down[key] then
            down[key] = nil
            heldSince[key] = nil
            lastRepeat[key] = nil
        end
        push(key, false)
    end
end

-- Codeware 콜백 등록. onInit 에서 한 번 호출한다.
function Input.init()
    local ok, err = pcall(function()
        local callbackSystem = Game.GetCallbackSystem()
        if not callbackSystem then
            error("Game.GetCallbackSystem() is not available (Codeware not installed?)")
        end
        listener = NewProxy({
            OnKeyInput = {
                args = { "handle:KeyInputEvent" },
                callback = function(evt)
                    if errorCount >= MAX_ERRORS then
                        return
                    end
                    local cbOk, cbErr = pcall(onKeyEvent, evt)
                    if not cbOk then
                        errorCount = errorCount + 1
                        Util.log("key callback error: " .. tostring(cbErr))
                    end
                end,
            },
        })
        -- 마지막 인자 true: 세션(세이브 로드)이 바뀌어도 콜백 유지
        callbackSystem:RegisterCallback("Input/Key", listener:Target(), listener:Function("OnKeyInput"), true)
    end)
    Input.available = ok
    Input.error = (not ok) and tostring(err) or nil
    if ok then
        Util.log("Codeware key input connected")
    else
        Util.log("Codeware key input NOT available: " .. tostring(err))
    end
    return ok
end

-- onUpdate 에서 호출. 쌓인 키 이벤트를 handler 로 넘기고, 반복 입력을 만든다.
function Input.poll()
    if #queue > 0 then
        local events = queue
        queue = {}
        if Input.handler then
            for i = 1, #events do
                Input.handler(events[i][1], events[i][2], false)
            end
        end
    end

    local t = Util.now()
    for key in pairs(Input.repeatKeys) do
        local since = heldSince[key]
        if down[key] and since then
            local held = t - since
            if held > STUCK_TIMEOUT then
                down[key] = nil
                heldSince[key] = nil
                lastRepeat[key] = nil
            elseif held >= REPEAT_DELAY and (t - (lastRepeat[key] or 0)) >= REPEAT_INTERVAL then
                lastRepeat[key] = t
                if Input.handler then
                    Input.handler(key, true, true)
                end
            end
        end
    end
end

function Input.isDown(key)
    return down[key] == true
end

-- 최근 seconds 초 안에 key 의 Press 이벤트가 있었는가
function Input.pressedWithin(key, seconds)
    local t = pressedAt[key]
    return t ~= nil and (Util.now() - t) <= seconds
end

function Input.lastPressTime(key)
    return pressedAt[key]
end

-- 눌림 상태 초기화. CET 오버레이가 열리면 키 떼는 이벤트가 게임까지 오지 않으므로 그때 호출한다.
function Input.reset()
    down = {}
    heldSince = {}
    lastRepeat = {}
    queue = {}
end

-- "IK_Insert" -> "Insert"
function Input.keyLabel(key)
    return (tostring(key):gsub("^IK_", ""))
end

return Input
