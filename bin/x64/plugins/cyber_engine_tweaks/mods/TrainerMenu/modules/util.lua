-- 공용 유틸리티
local Util = {}

-- 벽시계 시간(초). CET 샌드박스의 os.clock 은 Windows 에서 프로세스 시작 후 경과 시간이다.
function Util.now()
    return os.clock()
end

function Util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Util.round(v, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(v * m + 0.5) / m
end

-- CET 콘솔 + 모드 로그 파일(TrainerMenu.log) 양쪽에 남긴다.
function Util.log(msg)
    msg = "[TrainerMenu] " .. tostring(msg)
    print(msg)
    if spdlog and spdlog.info then
        pcall(spdlog.info, msg)
    end
end

-- 게임 API 호출은 로딩 화면/메인 메뉴 등에서 언제든 실패할 수 있으므로 전부 이걸로 감싼다.
-- 성공: true, 반환값 / 실패: false, 에러 문자열
function Util.try(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then
        return true, res
    end
    return false, tostring(res)
end

-- ImGui 플래그 합치기 (bit32 가 있으면 쓰고, 없으면 단일 비트 플래그의 합)
function Util.flags(...)
    local list = { ... }
    if bit32 and bit32.bor then
        local r = 0
        for i = 1, #list do
            r = bit32.bor(r, list[i])
        end
        return r
    end
    local seen, r = {}, 0
    for i = 1, #list do
        local f = list[i]
        if not seen[f] then
            seen[f] = true
            r = r + f
        end
    end
    return r
end

-- 숫자에 천 단위 쉼표
function Util.comma(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then
        out = out:sub(2)
    end
    return out
end

return Util
