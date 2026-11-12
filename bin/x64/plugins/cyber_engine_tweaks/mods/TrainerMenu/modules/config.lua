-- 설정 저장/불러오기 (모드 폴더의 config.json)
local Util = require("modules/util")

local Config = {}

local FILE = "config.json"

-- 메뉴 열기 키로 고를 수 있는 키 목록 (Codeware 의 EInputKey 이름)
Config.TOGGLE_KEYS = {
    "IK_F1", "IK_F2", "IK_F3", "IK_F4", "IK_F5", "IK_F6",
    "IK_F7", "IK_F8", "IK_F9", "IK_F10", "IK_F11", "IK_F12",
    "IK_Insert", "IK_Delete", "IK_Home", "IK_End", "IK_PageUp", "IK_PageDown",
}

Config.SAVE_SLOTS = 5

local function defaults()
    return {
        language = "ko",        -- "ko" | "en"
        toggleKey = "IK_Insert", -- 메뉴 열기/닫기 키
        blockQuickSave = true,  -- 메뉴 키를 F5 로 바꿨을 때 게임의 F5 퀵세이브를 막는다
        noclipSpeed = 10,       -- 노클립 이동 속도 (m/s)
        positions = {},         -- 저장한 위치: ["1"] = { x=, y=, z=, yaw= }
    }
end

Config.data = defaults()

local function isValidToggleKey(key)
    for _, k in ipairs(Config.TOGGLE_KEYS) do
        if k == key then
            return true
        end
    end
    return false
end

-- 파일에서 읽은 값을 검증해서 기본값 위에 덮어쓴다. 타입이 이상하면 기본값 유지.
local function merge(loaded)
    local d = defaults()
    if type(loaded) ~= "table" then
        return d
    end
    if loaded.language == "ko" or loaded.language == "en" then
        d.language = loaded.language
    end
    if type(loaded.toggleKey) == "string" and isValidToggleKey(loaded.toggleKey) then
        d.toggleKey = loaded.toggleKey
    end
    if type(loaded.blockQuickSave) == "boolean" then
        d.blockQuickSave = loaded.blockQuickSave
    end
    if type(loaded.noclipSpeed) == "number" then
        d.noclipSpeed = Util.clamp(loaded.noclipSpeed, 1, 100)
    end
    if type(loaded.positions) == "table" then
        for slot = 1, Config.SAVE_SLOTS do
            local p = loaded.positions[tostring(slot)]
            if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
                d.positions[tostring(slot)] = { x = p.x, y = p.y, z = p.z, yaw = type(p.yaw) == "number" and p.yaw or 0 }
            end
        end
    end
    return d
end

function Config.load()
    local ok, result = pcall(function()
        local file = io.open(FILE, "r")
        if not file then
            return nil
        end
        local text = file:read("*a")
        file:close()
        if not text or text == "" then
            return nil
        end
        return json.decode(text)
    end)
    if not ok then
        Util.log("config.json 읽기 실패, 기본값 사용: " .. tostring(result))
        result = nil
    end
    Config.data = merge(result)
    return Config.data
end

function Config.save()
    local ok, err = pcall(function()
        local text = json.encode(Config.data)
        local file = io.open(FILE, "w")
        if not file then
            error("cannot open " .. FILE .. " for writing")
        end
        file:write(text)
        file:close()
    end)
    if not ok then
        Util.log("config.json 저장 실패: " .. tostring(err))
    end
    return ok
end

return Config
