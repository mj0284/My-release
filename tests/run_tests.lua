-- F5 Trainer 테스트 (게임 없이 LuaJIT 으로 실행)
--
--   luajit tests/run_tests.lua
--
-- cet_mock.lua 의 가짜 CET/게임 환경 위에서 모드를 통째로 불러와
-- 키 입력 -> 메뉴 조작 -> 게임 API 호출까지 흐름을 검증한다.
-- 주의: 가짜 환경이므로 "게임 안에서 실제로 그렇게 동작한다"는 보장은 아니다.
local scriptDir = (arg and arg[0] or "tests/run_tests.lua"):match("^(.*)/[^/]*$") or "."
local repoRoot = scriptDir .. "/.."
local modRoot = repoRoot .. "/bin/x64/plugins/cyber_engine_tweaks/mods/F5Trainer"

local Mock = dofile(scriptDir .. "/cet_mock.lua")

local tmpBase = os.getenv("F5T_TEST_TMP") or os.tmpname() .. "_f5trainer"
os.execute("mkdir -p '" .. tmpBase .. "'")

local passed, failed = 0, {}
local testIndex = 0

local function newWorld(opts)
    opts = opts or {}
    testIndex = testIndex + 1
    local dataDir = opts.dataDir or (tmpBase .. "/run" .. testIndex)
    os.execute("mkdir -p '" .. dataDir .. "'")
    local world = Mock.install({
        codeware = opts.codeware,
        modRoot = modRoot,
        dataDir = dataDir,
        jsonPath = scriptDir .. "/vendor/json.lua",
    })
    world.dataDir = dataDir
    return world
end

local current = nil

local function test(name, fn)
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    if current then
        current.uninstall()
        current = nil
    end
    if ok then
        passed = passed + 1
        io.write("  ok    ", name, "\n")
    else
        failed[#failed + 1] = name
        io.write("  FAIL  ", name, "\n", err, "\n")
    end
end

-- 모드를 불러온 world 를 만든다.
local function boot(opts)
    current = newWorld(opts)
    current.mod = current.loadMod()
    return current
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, what)
    if not value then
        error((what or "value") .. ": expected truthy, got " .. tostring(value), 2)
    end
end

local function near(actual, expected, tolerance, what)
    if math.abs(actual - expected) > (tolerance or 1e-6) then
        error(string.format("%s: expected ~%s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function readFile(world, name)
    local file = world.realOpen(world.dataDir .. "/" .. name, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

-- 메뉴를 열고 루트에서 index 번째 하위 메뉴로 들어간다.
local function openSubmenu(world, index)
    world.tap("IK_F5")
    for _ = 2, index do world.tap("IK_Down") end
    world.tap("IK_Enter")
end

local function down(world, times)
    for _ = 1, times do world.tap("IK_Down") end
end

local PLAYER, PROGRESS, ITEMS, WORLD, TELEPORT, SETTINGS = 1, 2, 3, 4, 5, 6

----------------------------------------------------------------------------------------------------
io.write("F5 Trainer tests\n")

test("loads and registers everything with CET", function()
    local w = boot()
    truthy(w.mod and w.mod.ready, "mod ready")
    for _, event in ipairs({ "onInit", "onUpdate", "onDraw", "onOverlayOpen", "onOverlayClose", "onShutdown" }) do
        truthy(w.events[event], event .. " registered")
    end
    truthy(w.hotkeys["f5trainer_toggle"], "CET hotkey registered")
    truthy(w.overrides["gameuiInGameMenuGameController.HandleQuickSave"], "quick save override")
    truthy(w.observers["PlayerPuppet.OnGameAttached"], "session observer")
    eq(w.count("RegisterCallback"), 1, "Codeware Input/Key callback")
    w.frames(3)
    eq(#w.ui.rows, 0, "menu hidden at start")
end)

test("F5 opens and closes the menu", function()
    local w = boot()
    w.tap("IK_F5")
    eq(#w.ui.rows, 6, "root menu rows")
    truthy(w.hasText("F5 트레이너"), "korean title")
    eq(w.selectedRow(), 1, "cursor on first row")
    w.tap("IK_F5")
    eq(#w.ui.rows, 0, "menu closed")
end)

test("holding F5 does not flicker the menu", function()
    local w = boot()
    w.key("IK_F5", "IACT_Press")
    w.frames(5)
    w.key("IK_F5", "IACT_Press") -- OS 키 반복으로 Press 가 또 오는 경우
    w.frames(60, 0.05)
    eq(#w.ui.rows, 6, "still open after holding")
    w.key("IK_F5", "IACT_Release")
    w.frame()
    eq(#w.ui.rows, 6, "release does not toggle")
end)

test("arrow keys navigate, wrap around, Backspace goes back and closes", function()
    local w = boot()
    w.tap("IK_F5")
    w.tap("IK_Down")
    eq(w.selectedRow(), 2, "moved down")
    w.tap("IK_Up") w.tap("IK_Up")
    eq(w.selectedRow(), 6, "wrapped to last")
    w.tap("IK_Down")
    eq(w.selectedRow(), 1, "wrapped to first")
    w.tap("IK_Enter")
    truthy(w.hasText("> 플레이어"), "entered Player submenu")
    eq(#w.ui.rows, 10, "player rows")
    w.tap("IK_Backspace")
    eq(#w.ui.rows, 6, "back at root")
    w.tap("IK_Backspace")
    eq(#w.ui.rows, 0, "Backspace at root closes")
end)

test("numpad keys work as navigation too", function()
    local w = boot()
    w.tap("IK_F5")
    w.tap("IK_NumPad2")
    eq(w.selectedRow(), 2, "numpad 2 = down")
    w.tap("IK_NumPad8")
    eq(w.selectedRow(), 1, "numpad 8 = up")
    w.tap("IK_NumPad5")
    eq(#w.ui.rows, 10, "numpad 5 = select")
    w.tap("IK_NumPad0")
    eq(#w.ui.rows, 6, "numpad 0 = back")
end)

test("holding Down repeats, and a stuck key eventually stops", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    w.key("IK_Down", "IACT_Press")
    w.frames(10, 0.02) -- 0.2초: 아직 반복 전
    eq(w.selectedRow(), 2, "single step before repeat delay")
    w.frames(30, 0.02) -- +0.6초
    local index = w.selectedRow()
    truthy(index ~= 2, "cursor kept moving while held (now at " .. tostring(index) .. ")")
    w.key("IK_Down", "IACT_Release")
    w.frames(5)
    local stopped = w.selectedRow()
    w.frames(30, 0.02)
    eq(w.selectedRow(), stopped, "stops after release")

    -- 떼는 이벤트를 놓친 경우: 일정 시간 뒤 반복이 멈춰야 한다
    w.key("IK_Down", "IACT_Press")
    w.frames(600, 0.02) -- 12초
    local afterTimeout = w.selectedRow()
    w.frames(50, 0.02)
    eq(w.selectedRow(), afterTimeout, "stuck key no longer repeats")
end)

test("keys are ignored while the menu is closed", function()
    local w = boot()
    w.tap("IK_Enter") w.tap("IK_Down") w.tap("IK_Enter")
    eq(#w.ui.rows, 0, "menu still closed")
    eq(#w.requests, 0, "no requests sent")
    eq(next(w.godModes), nil, "nothing toggled")
end)

test("god mode: applies, keeps health full, re-applies, and removes", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    w.tap("IK_Enter") -- 무적
    w.frames(20)
    truthy(w.godModes["Invulnerable|F5Trainer"], "invulnerable added")
    truthy((w.pools.Health or 0) > 0, "health refilled")
    truthy(w.hasText("켜짐"), "shows ON")

    w.godModes = {} -- 게임이 갓모드를 지운 상황
    w.frames(20)
    truthy(w.godModes["Invulnerable|F5Trainer"], "re-applied")

    w.tap("IK_Enter")
    w.frames(20)
    eq(w.godModes["Invulnerable|F5Trainer"], nil, "removed when turned off")
    local fills = w.pools.Health
    w.frames(30)
    eq(w.pools.Health, fills, "no more refills when off")
end)

test("infinite stamina / RAM / oxygen refill only their own pools", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 1) w.tap("IK_Enter") -- 무한 스태미나
    w.frames(30)
    truthy((w.pools.Stamina or 0) > 0, "stamina refilled")
    eq(w.pools.Memory, nil, "RAM untouched")
    eq(w.pools.Health, nil, "health untouched")
    down(w, 1) w.tap("IK_Enter") -- 무한 RAM
    down(w, 1) w.tap("IK_Enter") -- 무한 산소
    w.frames(30)
    truthy((w.pools.Memory or 0) > 0, "RAM refilled")
    truthy((w.pools.Oxygen or 0) > 0, "oxygen refilled")
end)

test("infinite ammo: sets the game flag, tops up reserves, respects the game's own flag", function()
    local w = boot()
    w.inventory["Ammo.HandgunAmmo"] = 10
    w.inventory["Ammo.RifleAmmo"] = 400
    openSubmenu(w, PLAYER)
    down(w, 4) w.tap("IK_Enter") -- 무한 탄약
    w.frames(200) -- 3초 이상
    truthy(w.equipFlags.InfiniteAmmo, "flag set")
    eq(w.inventory["Ammo.HandgunAmmo"], 210, "low ammo topped up once")
    eq(w.inventory["Ammo.RifleAmmo"], 400, "plenty of ammo left alone")

    w.tap("IK_Enter")
    w.frames(5)
    eq(w.equipFlags.InfiniteAmmo, nil, "flag removed")

    w.tap("IK_Enter")
    w.frames(20)
    w.gameOwnsInfiniteAmmo = true -- 차량 전투 중
    w.tap("IK_Enter")
    w.frames(5)
    truthy(w.equipFlags.InfiniteAmmo, "flag kept while the game itself uses it")
end)

test("carry weight and move speed use stat modifiers and clean up after themselves", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 5) w.tap("IK_Enter") -- 소지 무게 무제한
    eq(#w.statMods, 1, "carry modifier added")
    eq(w.statMods[1].stat, "CarryCapacity", "carry stat")
    eq(w.statMods[1].kind, "Additive", "carry type")

    down(w, 2) -- 이동 속도 배율
    w.tap("IK_Right")
    eq(#w.statMods, 2, "speed modifier added")
    eq(w.statMods[2].stat, "MaxSpeed", "speed stat")
    eq(w.statMods[2].kind, "Multiplier", "speed type")
    near(w.statMods[2].value, 1.5, 1e-6, "x1.5")
    w.tap("IK_Right")
    eq(#w.statMods, 2, "old speed modifier replaced, not stacked")
    near(w.statMods[2].value, 2.0, 1e-6, "x2.0")
    truthy(w.hasText("< x2.0 >"), "value shown")
    w.tap("IK_Left") w.tap("IK_Left")
    eq(#w.statMods, 1, "speed modifier removed at x1.0")
    w.tap("IK_Left")
    near(w.statMods[2].value, 0.5, 1e-6, "x0.5")
    w.tap("IK_Left")
    near(w.statMods[2].value, 0.5, 1e-6, "clamped at the lowest option")
    truthy(not w.hasText("실패"), "stepping past the end is a quiet no-op, not an error")
end)

test("stat modifiers are re-applied after loading a save", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 5) w.tap("IK_Enter")
    down(w, 2) w.tap("IK_Right") w.tap("IK_Right")
    eq(#w.statMods, 2, "two modifiers before load")

    w.statMods = {} -- 세이브 로드: 게임 쪽 모디파이어가 사라짐
    w.observers["PlayerPuppet.OnGameAttached"]()
    w.frames(30, 0.05)
    eq(#w.statMods, 2, "re-applied after session start")
end)

test("re-syncing within the same session does not stack stat modifiers", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 5) w.tap("IK_Enter")
    down(w, 2) w.tap("IK_Right")
    eq(#w.statMods, 2, "two modifiers")

    -- 모디파이어가 게임에 그대로 남아 있는데 재동기화가 도는 경우 (모드 리로드 직후, 플레이어 재부착 등)
    w.observers["PlayerPuppet.OnGameAttached"]()
    w.frames(30, 0.05)
    eq(#w.statMods, 2, "still two, not four")

    w.tap("IK_Left") -- 속도 x1.0
    eq(#w.statMods, 1, "speed modifier fully removed")
    w.tap("IK_Up") w.tap("IK_Up") w.tap("IK_Enter") -- 소지 무게 끔
    eq(#w.statMods, 0, "carry modifier fully removed")
end)

test("heal refills health, stamina and RAM once", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 6) w.tap("IK_Enter")
    eq(w.pools.Health, 1, "health") eq(w.pools.Stamina, 1, "stamina") eq(w.pools.Memory, 1, "RAM")
    truthy(w.hasText("완료"), "status message shown")
end)

test("noclip moves along the camera with WASD/Space/Ctrl/Shift", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 8) w.tap("IK_Enter") -- 노클립
    w.frames(5)
    truthy(w.teleports > 0, "holds position by teleporting every frame")
    near(w.pos.y, 20, 1e-6, "no drift without input")
    truthy(w.hasText("WASD"), "noclip hint shown")

    w.key("IK_W", "IACT_Press")
    w.frames(50, 0.02) -- 1초, 10 m/s
    w.key("IK_W", "IACT_Release")
    w.frame()
    near(w.pos.y, 30, 0.5, "moved forward ~10m")
    near(w.pos.x, 10, 1e-6, "no sideways movement")

    w.key("IK_Space", "IACT_Press")
    w.frames(50, 0.02)
    w.key("IK_Space", "IACT_Release")
    w.frame()
    near(w.pos.z, 40, 0.5, "moved up ~10m")

    w.key("IK_LShift", "IACT_Press") w.key("IK_A", "IACT_Press")
    w.frames(50, 0.02)
    w.key("IK_A", "IACT_Release") w.key("IK_LShift", "IACT_Release")
    w.frame()
    near(w.pos.x, -30, 2, "moved left ~40m with Shift")

    w.key("IK_LControl", "IACT_Press")
    w.frames(25, 0.02)
    w.key("IK_LControl", "IACT_Release")
    w.frame()
    near(w.pos.z, 35, 0.5, "moved down ~5m")

    local before = w.teleports
    w.tap("IK_Enter") -- 끄기
    w.frames(10)
    truthy(w.teleports <= before + 1, "stops teleporting when off")
end)

test("a frame hitch cannot fling the player in noclip", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 8) w.tap("IK_Enter")
    w.key("IK_W", "IACT_Press")
    w.frame(5.0) -- 5초짜리 프레임
    truthy(w.pos.y - 20 <= 1.01, "step clamped (moved " .. (w.pos.y - 20) .. "m)")
end)

test("money, level, street cred and points go through the right requests", function()
    local w = boot()
    openSubmenu(w, PROGRESS)
    w.tap("IK_Enter")
    eq(w.inventory["Items.money"], 10000, "+10,000")
    truthy(w.hasText("+10,000"), "status shows amount")
    down(w, 2) w.tap("IK_Enter")
    eq(w.inventory["Items.money"], 1010000, "+1,000,000")

    down(w, 1) w.tap("IK_Enter") -- 레벨 +1
    eq(w.stats.Level, 21, "level +1")
    down(w, 1) w.tap("IK_Enter") -- 레벨 +5
    eq(w.stats.Level, 26, "level +5")
    down(w, 2) w.tap("IK_Enter") -- 스트리트 크레드 +5
    eq(w.stats.StreetCred, 15, "street cred +5")
    down(w, 2) w.tap("IK_Enter") -- 특성 +5
    eq(w.stats.DevPoints_Attribute, 5, "attribute points")
    down(w, 2) w.tap("IK_Enter") -- 퍽 +5
    eq(w.stats.DevPoints_Primary, 5, "perk points")
    down(w, 1) w.tap("IK_Enter") -- 렐릭 +1
    eq(w.stats.DevPoints_Espionage, 1, "relic points")
end)

test("level is capped and says so", function()
    local w = boot()
    w.stats.Level = 58
    openSubmenu(w, PROGRESS)
    down(w, 4) w.tap("IK_Enter") -- 레벨 +5
    eq(w.stats.Level, 60, "clamped to 60")
    local requests = #w.requests
    w.tap("IK_Enter")
    eq(#w.requests, requests, "no request at max level")
    truthy(w.hasText("최대치"), "max message")
end)

test("level cap comes from the game (50 without the expansion)", function()
    local w = boot()
    w.maxLevels.Level = 50
    w.stats.Level = 49
    openSubmenu(w, PROGRESS)
    down(w, 4) w.tap("IK_Enter") -- 레벨 +5
    eq(w.stats.Level, 50, "clamped to the game's cap")
    w.tap("IK_Enter")
    truthy(w.hasText("(50)"), "reports the real cap")
end)

test("level still works when the cap query is unavailable", function()
    local w = boot()
    w.brokenProficiencyQuery = true
    openSubmenu(w, PROGRESS)
    down(w, 3) w.tap("IK_Enter") -- 레벨 +1
    eq(w.stats.Level, 21, "falls back to the stat value")
end)

test("give items adds every item in the set", function()
    local w = boot()
    openSubmenu(w, ITEMS)
    w.tap("IK_Enter")
    eq(w.inventory["Ammo.SniperRifleAmmo"], 500, "ammo")
    down(w, 1) w.tap("IK_Enter")
    eq(w.inventory["Items.LegendaryMaterial1"], 200, "crafting components")
    down(w, 1) w.tap("IK_Enter")
    eq(w.inventory["Items.QuickHackLegendaryMaterial1"], 100, "quickhack components")
end)

test("time only moves forward and keeps the day count", function()
    local w = boot() -- 3일째 10:30
    openSubmenu(w, WORLD)
    w.tap("IK_Enter") -- 08:00 -> 이미 지났으므로 다음 날 08:00
    eq(w.time, 4 * 86400 + 8 * 3600, "next day's 08:00")
    down(w, 1) w.tap("IK_Enter") -- 12:00 -> 같은 날
    eq(w.time, 4 * 86400 + 12 * 3600, "same day 12:00")
    down(w, 3) w.tap("IK_Enter") -- +1시간
    eq(w.time, 4 * 86400 + 13 * 3600, "+1 hour")
    truthy(w.hasText("13:00"), "status shows new time")
    down(w, 1) -- 자정 항목은 건너뛰고 위에서 확인: 위로 두 칸
    w.tap("IK_Up") w.tap("IK_Up") w.tap("IK_Enter") -- 자정
    eq(w.time, 5 * 86400, "midnight rolls to the next day")
end)

test("game speed sets and clears time dilation", function()
    local w = boot()
    openSubmenu(w, WORLD)
    down(w, 5)
    w.tap("IK_Left")
    near(w.dilation.consoleCommand, 0.75, 1e-6, "x0.75")
    w.tap("IK_Left") w.tap("IK_Left") w.tap("IK_Left") w.tap("IK_Left")
    near(w.dilation.consoleCommand, 0.1, 1e-6, "clamped at x0.1")
    for _ = 1, 4 do w.tap("IK_Right") end
    eq(w.dilation.consoleCommand, nil, "x1.0 removes the dilation")
end)

test("police toggle locks the prevention system and wanted level can be cleared", function()
    local w = boot()
    w.frames(80) -- 세션 시작 동기화
    openSubmenu(w, WORLD)
    down(w, 6) w.tap("IK_Enter") -- 수배 해제
    eq(w.wantedLevel, "Heat_0", "wanted level cleared")
    down(w, 1) w.tap("IK_Enter") -- 경찰 비활성화
    truthy(w.policeLocks.F5Trainer, "police locked")
    eq(w.policeEnabled, false, "police system off")
    w.tap("IK_Enter")
    eq(w.policeLocks.F5Trainer, nil, "police unlocked")
    eq(w.policeEnabled, true, "police system back on")
end)

test("clearing the wanted level does not quietly re-enable disabled police", function()
    local w = boot()
    w.frames(80)
    openSubmenu(w, WORLD)
    down(w, 7) w.tap("IK_Enter") -- 경찰 비활성화
    eq(w.policeEnabled, false, "off")
    w.tap("IK_Up") w.tap("IK_Enter") -- 수배 해제: 게임이 시스템을 다시 켠다
    eq(w.wantedLevel, "Heat_0", "wanted level cleared")
    eq(w.policeEnabled, false, "still off afterwards")
    truthy(w.policeLocks.F5Trainer, "lock still held")
end)

test("disabled police are re-asserted after loading a save that had them re-enabled", function()
    local w = boot()
    w.frames(80)
    openSubmenu(w, WORLD)
    down(w, 7) w.tap("IK_Enter")
    w.policeEnabled = true -- 잠금은 남아 있는데 시스템만 켜진 상태로 불러온 경우
    w.observers["PlayerPuppet.OnGameAttached"]()
    w.frames(100)
    eq(w.policeEnabled, false, "off again")
end)

test("another source's police lock is left alone", function()
    local w = boot()
    w.policeLocks.some_quest = true
    w.policeEnabled = false
    w.frames(100) -- 세션 시작 동기화
    eq(w.policeEnabled, false, "quest lock still in effect")
    openSubmenu(w, WORLD)
    down(w, 7) w.tap("IK_Enter") w.tap("IK_Enter") -- 켰다 끔
    eq(w.policeEnabled, false, "still off because of the quest's own lock")
    truthy(w.policeLocks.some_quest, "quest lock untouched")
end)

test("a police lock left in a save is cleared on the next session", function()
    local w = boot()
    w.policeLocks.F5Trainer = true -- 이전 플레이에서 켠 채로 저장된 세이브
    w.frames(100)
    eq(w.policeLocks.F5Trainer, nil, "stale lock removed")
    eq(w.policeEnabled, true, "police back on")
end)

test("teleport: save slot, load slot, tracked map pin", function()
    local w = boot()
    openSubmenu(w, TELEPORT)
    w.tap("IK_Enter")
    truthy(w.hasText("핀이 없습니다"), "no pin message")
    eq(w.teleports, 0, "no teleport without a pin")

    down(w, 1) w.tap("IK_Enter")
    truthy(w.hasText("저장된 위치가 없습니다"), "empty slot message")

    down(w, 5) w.tap("IK_Enter") -- 현재 위치 저장 - 슬롯 1
    truthy(readFile(w, "config.json"):find('"x":10', 1, true), "slot written to config.json")

    w.pos = { x = 500.0, y = 600.0, z = 70.0 }
    w.yaw = 10.0
    for _ = 1, 5 do w.tap("IK_Up") end
    truthy(w.hasRow("(10, 20, 30)"), "slot shows saved coordinates")
    w.tap("IK_Enter")
    near(w.pos.x, 10, 1e-6, "x restored") near(w.pos.z, 30, 1e-6, "z restored") near(w.yaw, 90, 1e-6, "yaw restored")

    w.mappin = { x = -100.0, y = 200.0, z = 5.0 }
    w.tap("IK_Up") w.tap("IK_Enter")
    near(w.pos.x, -100, 1e-6, "pin x") near(w.pos.z, 6, 1e-6, "pin z lifted 1m")
end)

test("nothing can be switched on outside of gameplay", function()
    local w = boot()
    w.preGame = true -- 메인 메뉴
    w.frames(80, 0.05)
    openSubmenu(w, PLAYER)
    w.tap("IK_Enter")
    truthy(w.hasText("게임 플레이 중에만"), "not-in-game message")
    eq(next(w.godModes), nil, "god mode not applied")
    w.tap("IK_Backspace") w.tap("IK_Down") w.tap("IK_Enter") w.tap("IK_Enter")
    eq(w.inventory["Items.money"], nil, "no money in the main menu")

    w.preGame = false
    w.hasPlayer = false -- 로딩 화면
    w.frames(80, 0.05)
    w.tap("IK_Enter")
    eq(w.inventory["Items.money"], nil, "no money without a player")
end)

test("settings persist: language, menu key, quick save option", function()
    local w = boot()
    local dataDir = w.dataDir
    openSubmenu(w, SETTINGS)
    w.tap("IK_Right") -- 언어 -> English
    truthy(w.hasText("F5 TRAINER"), "switched to English")
    truthy(w.hasText("< English >"), "language value")
    down(w, 1) w.tap("IK_Right") -- 메뉴 키 F5 -> F6
    truthy(w.hasText("< F6 >"), "key value")
    down(w, 1) w.tap("IK_Enter") -- 퀵세이브 막기 끔

    w.tap("IK_F5")
    eq(#w.ui.rows, 3, "old key no longer toggles")
    w.tap("IK_F6")
    eq(#w.ui.rows, 0, "new key closes")
    current.uninstall()

    current = newWorld({ dataDir = dataDir })
    local w2 = current
    w2.loadMod()
    w2.tap("IK_F6")
    eq(#w2.ui.rows, 6, "saved key works after restart")
    truthy(w2.hasText("F5 TRAINER"), "saved language")
    w2.tap("IK_Up") w2.tap("IK_Enter")
    truthy(w2.hasText("OFF"), "saved quick save option")
end)

test("a corrupt or hostile config.json falls back to defaults", function()
    current = newWorld()
    local w = current
    local file = w.realOpen(w.dataDir .. "/config.json", "w")
    file:write('{"language":"xx","toggleKey":"IK_W","noclipSpeed":"fast","positions":{"1":{"x":"a"}},"blockQuickSave":3}')
    file:close()
    w.loadMod()
    w.tap("IK_F5")
    eq(#w.ui.rows, 6, "F5 still opens")
    truthy(w.hasText("F5 트레이너"), "default language")
    current.uninstall()

    current = newWorld()
    w = current
    file = w.realOpen(w.dataDir .. "/config.json", "w")
    file:write("{{{ not json")
    file:close()
    truthy(w.loadMod().ready, "loads with broken json")
end)

test("quick save: F5 for the trainer does not save (key event first)", function()
    local w = boot()
    local controller = w.quickSaveController()
    w.key("IK_F5", "IACT_Press")
    controller:HandleQuickSave()
    w.frames(30)
    w.key("IK_F5", "IACT_Release")
    w.frames(30)
    eq(w.quickSaves, 0, "no quick save")
end)

test("quick save: F5 for the trainer does not save (game action first)", function()
    local w = boot()
    local controller = w.quickSaveController()
    controller:HandleQuickSave() -- 키 이벤트보다 게임 액션이 먼저 온 경우
    w.key("IK_F5", "IACT_Press")
    w.frames(30)
    w.key("IK_F5", "IACT_Release")
    w.frames(30)
    eq(w.quickSaves, 0, "no quick save")
end)

test("quick save: a save requested by another key still happens, exactly once", function()
    local w = boot()
    local controller = w.quickSaveController()
    controller:HandleQuickSave()
    eq(w.quickSaves, 0, "deferred for a moment")
    w.frames(30)
    eq(w.quickSaves, 1, "saved after the short delay")
    w.frames(60)
    eq(w.quickSaves, 1, "not saved twice")
end)

test("quick save: untouched when the option is off or the menu key is not F5", function()
    local w = boot()
    local controller = w.quickSaveController()
    openSubmenu(w, SETTINGS)
    down(w, 2) w.tap("IK_Enter") -- 막기 끔
    w.frames(30)
    w.key("IK_F5", "IACT_Press")
    controller:HandleQuickSave()
    eq(w.quickSaves, 1, "saves immediately with the option off")
    w.key("IK_F5", "IACT_Release")
    w.frames(30)

    w.tap("IK_Enter") -- 다시 켬
    w.tap("IK_Up") w.tap("IK_Right") -- 메뉴 키 F6
    w.key("IK_F5", "IACT_Press")
    controller:HandleQuickSave()
    eq(w.quickSaves, 2, "F5 saves normally when the menu key is F6")
end)

test("without Codeware: usable with the mouse in the CET overlay", function()
    local w = boot({ codeware = false })
    truthy(w.mod.ready, "still loads")
    w.frames(3)
    eq(#w.ui.rows, 0, "hidden while the overlay is closed")

    w.events.onOverlayOpen()
    w.frame()
    eq(#w.ui.rows, 6, "shown together with the overlay")
    truthy(w.hasText("Codeware"), "explains what is missing")

    w.click = "돈 / 성장"
    w.frame() w.frame()
    eq(#w.ui.rows, 12, "click enters the submenu")
    w.click = "돈 +100,000"
    w.frame()
    eq(w.inventory["Items.money"], 100000, "click runs the action")

    w.clickButton = "<"
    w.frame() w.frame()
    eq(#w.ui.rows, 6, "back button")

    w.click = "플레이어"
    w.frame() w.frame()
    w.click = "노클립 (벽 통과 비행)"
    w.frame() w.frame()
    truthy(w.hasText("Codeware 가 필요한"), "noclip refuses without key input")
    eq(w.teleports, 0, "noclip not started")

    w.events.onOverlayClose()
    w.frame()
    eq(#w.ui.rows, 0, "hidden again with the overlay")

    local controller = w.quickSaveController()
    controller:HandleQuickSave()
    eq(w.quickSaves, 1, "quick save untouched without key input")
end)

test("overlay mode: left click cycles a value forward, right click backward, X closes", function()
    local w = boot()
    w.tap("IK_F5")
    w.events.onOverlayOpen()
    w.click = "월드"
    w.frame() w.frame()
    w.rightClick = "게임 속도 (슬로모션)"
    w.frame() w.frame()
    near(w.dilation.consoleCommand, 0.75, 1e-6, "right click steps back")
    w.click = "게임 속도 (슬로모션)"
    w.frame() w.frame()
    eq(w.dilation.consoleCommand, nil, "left click steps forward")

    w.key("IK_Down", "IACT_Press") -- 오버레이 중에는 키로 조작하지 않는다
    local index = w.selectedRow()
    w.frame()
    eq(w.selectedRow(), index, "keys ignored while the overlay is open")

    w.clickButton = "X"
    w.frame() w.frame()
    eq(#w.ui.rows, 0, "X closes")
end)

test("keys held when the overlay opens do not stay stuck", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    down(w, 8) w.tap("IK_Enter") -- 노클립
    w.key("IK_W", "IACT_Press")
    w.frames(10, 0.02)
    w.events.onOverlayOpen() -- 떼는 이벤트는 오버레이가 가져간다
    local y = w.pos.y
    w.frames(50, 0.02)
    near(w.pos.y, y, 1e-6, "stopped moving")
end)

test("CET hotkey toggles, but not twice for the same key press", function()
    local w = boot()
    w.hotkeys["f5trainer_toggle"]()
    w.frame()
    eq(#w.ui.rows, 6, "hotkey opens")
    w.key("IK_F5", "IACT_Press") -- Codeware 쪽에서 닫힘
    w.frame()
    w.key("IK_F5", "IACT_Release")
    w.hotkeys["f5trainer_toggle"]() -- 같은 키가 CET 에도 바인딩된 경우
    w.frame()
    eq(#w.ui.rows, 0, "closed once, not reopened")
end)

test("every menu page draws in both languages", function()
    for _, language in ipairs({ "ko", "en" }) do
        local w = boot()
        if language == "en" then
            openSubmenu(w, SETTINGS)
            w.tap("IK_Right")
            w.tap("IK_Backspace")
            w.tap("IK_F5")
        end
        for index = 1, 6 do
            openSubmenu(w, index)
            truthy(#w.ui.rows > 0, language .. " submenu " .. index .. " has rows")
            for _, label in ipairs(w.rowLabels()) do
                truthy(label ~= "" and not label:match("^[%l_]+$"), "untranslated label: " .. label)
            end
            w.tap("IK_Backspace")
            w.tap("IK_Backspace")
            eq(#w.ui.rows, 0, "closed")
            -- 다음 반복에서 커서가 루트 첫 줄이 아니므로 맞춰 준다
            w.tap("IK_F5")
            for _ = 2, index do w.tap("IK_Up") end
            w.tap("IK_F5")
        end
        current.uninstall()
        current = nil
    end
end)

test("an exploding game call is reported, not thrown", function()
    local w = boot()
    rawset(Game, "AddToInventory", function() error("boom from the game") end)
    openSubmenu(w, PROGRESS)
    w.tap("IK_Enter")
    truthy(w.hasText("실패"), "failure shown in the status line")
    truthy(w.hasText("boom from the game"), "with the reason")
    w.frames(10)
end)

test("shutdown undoes what was left in the game", function()
    local w = boot()
    openSubmenu(w, PLAYER)
    w.tap("IK_Enter")                 -- 무적
    down(w, 4) w.tap("IK_Enter")      -- 무한 탄약
    down(w, 1) w.tap("IK_Enter")      -- 소지 무게
    down(w, 2) w.tap("IK_Right")      -- 속도 x1.5
    w.tap("IK_Backspace")
    down(w, 3) w.tap("IK_Enter")      -- 월드
    down(w, 5) w.tap("IK_Left")       -- 게임 속도
    down(w, 2) w.tap("IK_Enter")      -- 경찰 비활성화
    w.frames(20)
    truthy(w.godModes["Invulnerable|F5Trainer"] and w.equipFlags.InfiniteAmmo and #w.statMods == 2
        and w.dilation.consoleCommand and w.policeLocks.F5Trainer, "everything active before shutdown")

    w.events.onShutdown()
    eq(next(w.godModes), nil, "god mode removed")
    eq(w.equipFlags.InfiniteAmmo, nil, "ammo flag removed")
    eq(#w.statMods, 0, "stat modifiers removed")
    eq(w.dilation.consoleCommand, nil, "time dilation removed")
    eq(w.policeLocks.F5Trainer, nil, "police unlocked")
    eq(w.policeEnabled, true, "police back on")
end)

----------------------------------------------------------------------------------------------------
os.execute("rm -rf '" .. tmpBase .. "'")
io.write(string.format("\n%d passed, %d failed\n", passed, #failed))
if #failed > 0 then
    for _, name in ipairs(failed) do io.write("  - ", name, "\n") end
    os.exit(1)
end
