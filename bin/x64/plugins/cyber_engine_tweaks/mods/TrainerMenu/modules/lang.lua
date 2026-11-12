-- UI 문자열 (한국어 / English)
-- 한글은 Windows 표시 언어가 한국어이거나 CET 설정의 Font > Language 가 Korean 이어야 보인다.
-- 글자가 ? 로 깨지면 설정 메뉴의 "Language" 항목을 English 로 바꾸면 된다.
local Lang = {}

local current = "ko"

local S = {
    title            = { ko = "트레이너 메뉴", en = "TRAINER MENU" },

    -- 메뉴 이름
    menu_player      = { ko = "플레이어", en = "Player" },
    menu_progress    = { ko = "돈 / 성장", en = "Money & Progression" },
    menu_items       = { ko = "아이템 지급", en = "Give Items" },
    menu_world       = { ko = "월드", en = "World" },
    menu_teleport    = { ko = "텔레포트", en = "Teleport" },
    menu_settings    = { ko = "설정", en = "Settings" },

    -- 플레이어
    god              = { ko = "무적", en = "God Mode" },
    inf_stamina      = { ko = "무한 스태미나", en = "Infinite Stamina" },
    inf_ram          = { ko = "무한 RAM", en = "Infinite RAM" },
    inf_oxygen       = { ko = "무한 산소", en = "Infinite Oxygen" },
    inf_ammo         = { ko = "무한 탄약", en = "Infinite Ammo" },
    heal             = { ko = "체력/스태미나/RAM 즉시 회복", en = "Refill Health / Stamina / RAM" },
    speed            = { ko = "이동 속도 배율", en = "Move Speed Multiplier" },
    carry            = { ko = "소지 무게 무제한", en = "Unlimited Carry Weight" },
    noclip           = { ko = "노클립 (벽 통과 비행)", en = "Noclip (Fly Through Walls)" },
    noclip_speed     = { ko = "노클립 속도", en = "Noclip Speed" },

    -- 돈 / 성장
    money_10k        = { ko = "돈 +10,000", en = "Money +10,000" },
    money_100k       = { ko = "돈 +100,000", en = "Money +100,000" },
    money_1m         = { ko = "돈 +1,000,000", en = "Money +1,000,000" },
    level_up1        = { ko = "레벨 +1", en = "Level +1" },
    level_up5        = { ko = "레벨 +5", en = "Level +5" },
    cred_up1         = { ko = "스트리트 크레드 +1", en = "Street Cred +1" },
    cred_up5         = { ko = "스트리트 크레드 +5", en = "Street Cred +5" },
    attr_1           = { ko = "특성 포인트 +1", en = "Attribute Point +1" },
    attr_5           = { ko = "특성 포인트 +5", en = "Attribute Points +5" },
    perk_1           = { ko = "퍽 포인트 +1", en = "Perk Point +1" },
    perk_5           = { ko = "퍽 포인트 +5", en = "Perk Points +5" },
    relic_1          = { ko = "렐릭 포인트 +1", en = "Relic Point +1" },

    -- 아이템
    give_ammo        = { ko = "탄약 지급 (종류별 500발)", en = "Give Ammo (500 each)" },
    give_mats        = { ko = "제작 부품 지급 (등급별 200개)", en = "Give Crafting Components (200 each)" },
    give_hackmats    = { ko = "퀵핵 부품 지급 (등급별 100개)", en = "Give Quickhack Components (100 each)" },

    -- 월드
    time_morning     = { ko = "시간: 아침 08:00", en = "Time: Morning 08:00" },
    time_noon        = { ko = "시간: 정오 12:00", en = "Time: Noon 12:00" },
    time_evening     = { ko = "시간: 저녁 19:00", en = "Time: Evening 19:00" },
    time_midnight    = { ko = "시간: 자정 00:00", en = "Time: Midnight 00:00" },
    time_plus1       = { ko = "시간 +1시간", en = "Time +1 Hour" },
    game_speed       = { ko = "게임 속도 (슬로모션)", en = "Game Speed (Slow Motion)" },
    clear_wanted     = { ko = "수배 해제", en = "Clear Wanted Level" },
    no_police        = { ko = "경찰 비활성화", en = "Disable Police" },

    -- 텔레포트
    tp_waypoint      = { ko = "지도 핀(추적 중인 위치)으로 이동", en = "Teleport to Tracked Map Pin" },
    tp_save          = { ko = "현재 위치 저장 - 슬롯 %d", en = "Save Position - Slot %d" },
    tp_load          = { ko = "저장 위치로 이동 - 슬롯 %d", en = "Go to Saved Position - Slot %d" },
    tp_empty         = { ko = "(비어 있음)", en = "(empty)" },

    -- 설정
    language         = { ko = "Language / 언어", en = "Language / 언어" },
    toggle_key       = { ko = "메뉴 열기 키", en = "Menu Toggle Key" },
    block_quicksave  = { ko = "메뉴 키가 F5 일 때 퀵세이브 막기", en = "Block Quick Save When Menu Key Is F5" },

    -- 값 표시
    on               = { ko = "켜짐", en = "ON" },
    off              = { ko = "꺼짐", en = "OFF" },

    -- 안내 / 상태 메시지
    hint_keys        = { ko = "방향키: 이동/조절   Enter: 선택   Backspace: 뒤로", en = "Arrows: move/adjust   Enter: select   Backspace: back" },
    hint_mouse       = { ko = "CET 오버레이: 마우스로 클릭해서 조작", en = "CET overlay: click with the mouse" },
    hint_noclip      = { ko = "노클립: WASD 이동, Space 상승, Ctrl 하강, Shift 가속", en = "Noclip: WASD move, Space up, Ctrl down, Shift fast" },
    no_codeware      = { ko = "Codeware 가 없어서 키 조작(메뉴 키/방향키)이 꺼져 있습니다. CET 오버레이에서 마우스로 쓰거나 Codeware 를 설치하세요.",
                         en = "Codeware not found: key controls (menu key/arrows) are off. Use the mouse in the CET overlay, or install Codeware." },
    need_codeware    = { ko = "Codeware 가 필요한 기능입니다", en = "This feature requires Codeware" },
    not_in_game      = { ko = "게임 플레이 중에만 쓸 수 있습니다", en = "Only available while in game" },
    failed           = { ko = "실패: %s", en = "Failed: %s" },
    done             = { ko = "완료: %s", en = "Done: %s" },
    no_waypoint      = { ko = "추적 중인 지도 핀이 없습니다 (지도에서 핀을 찍으세요)", en = "No tracked map pin (place a pin on the map)" },
    slot_empty       = { ko = "슬롯 %d 에 저장된 위치가 없습니다", en = "Slot %d has no saved position" },
    saved_slot       = { ko = "슬롯 %d 에 현재 위치 저장", en = "Position saved to slot %d" },
    teleported       = { ko = "이동 완료", en = "Teleported" },
    level_now        = { ko = "레벨 %d", en = "Level %d" },
    cred_now         = { ko = "스트리트 크레드 %d", en = "Street Cred %d" },
    max_reached      = { ko = "이미 최대치입니다 (%d)", en = "Already at maximum (%d)" },
    time_set         = { ko = "시간 변경: %02d:%02d", en = "Time set: %02d:%02d" },
    wanted_cleared   = { ko = "수배 해제 요청됨", en = "Wanted level cleared" },
    opened_with      = { ko = "%s: 열기/닫기", en = "%s: open/close" },
}

function Lang.set(code)
    if code == "ko" or code == "en" then
        current = code
    end
end

function Lang.get()
    return current
end

-- 문자열 조회. 추가 인자가 있으면 string.format 적용.
function Lang.t(key, ...)
    local entry = S[key]
    local text
    if entry then
        text = entry[current] or entry.en
    else
        text = key
    end
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then
            return formatted
        end
    end
    return text
end

return Lang
