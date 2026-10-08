-- C_NamePlate as pure Lua. The dll publishes data only:
--   AW_NamePlates     : "nameplate7" -> plate frame   (visible plates, keyed by the unit token)
--   AW_NamePlateGuids : "F130…"      -> plate frame   (guid, no 0x prefix)
--   AW_NamePlateTokens: "F130…"      -> "nameplate7"  (обратная связь guid -> токен)
--   AW_NamePlateList  : array of the visible plate frames
--
-- The functions are Lua closures on purpose. A C closure is a pointer into AwesomeWotlkLib.dll, and the
-- client validates function pointers before calling them on some paths: measured 29.09 21:18, that is
-- ERROR #134 "Invalid function pointer: 6FF73640" with "Current Addon function: GetNamePlateForUnit".
-- Upstream answers by widening the range of pointers the client accepts. This pack changes no client code,
-- so it needs neither of that: published data plus Lua closures cover every call site.

if type(C_NamePlate) ~= "table" then C_NamePlate = {} end

-- Пер-плейт отключение стекинга. У апстрима это C-функция, навешанная на рамку
-- (reference/awesome-upstream-07.10/src/AwesomeWotlkLib/NamePlateManager.cpp:417-436), то есть
-- lua_CFunction в данных клиента -- ровно то, за что этот клиент отдаёт ERROR #134 (29.09 21:18), а лечение
-- апстрима (расширенный диапазон допустимых указателей) -- измеренный носитель разрыва сессии. Поэтому
-- метод здесь Lua-функция на той же рамке, а состояние лежит в таблице AW_StackingDisabled под ключом
-- токена: dll читает её как обычные данные, указателей в кадре клиента нет.
--
-- getter честен настолько, насколько знает Lua: режим стекинга (nameplateStacking) и фильтр по стороне
-- решает dll, поэтому без этой переменной он возвращает nil -- «клиент об этом не спрашивали», а не
-- выдуманное true. Тот же порядок, что с проверкой существования CVar в окне настроек.
AW_StackingDisabled = AW_StackingDisabled or {}

local function tokenOf(plate)
    local plates = rawget(_G, "AW_NamePlates")
    if type(plates) ~= "table" then return nil end
    for token, p in pairs(plates) do
        if p == plate then return token end
    end
    return nil
end

local function decorate(plate)
    if type(plate) ~= "table" or plate.SetStackingEnabled then return plate end
    plate.SetStackingEnabled = function(self, on) C_NamePlate.SetStackingEnabled(self, on) end
    plate.GetStackingEnabled = function(self) return C_NamePlate.GetStackingEnabled(self) end
    return plate
end

-- Функциональная форма обязательна, а не только метод на рамке: decorate навешивается в момент выдачи,
-- а аддон может держать рамку, взятую прямо из таблицы dll (наш AWDistance читает AW_NamePlates именно
-- так). Ключ от этого не меняется -- таблица одна и та же.
function C_NamePlate.SetStackingEnabled(plate, on)
    local token = type(plate) == "table" and tokenOf(plate) or nil
    if not token then return end
    if on then AW_StackingDisabled[token] = nil else AW_StackingDisabled[token] = true end
end

function C_NamePlate.GetStackingEnabled(plate)
    local mode = GetCVar and tonumber(GetCVar("nameplateStacking"))
    if not mode then return nil end
    local token = type(plate) == "table" and tokenOf(plate) or nil
    -- рамка, которой нет среди опубликованных плейтов: состояния не знает никто, и врать про него
    -- незачем -- nil, а не вычисленное true
    if not token then return nil end
    return mode ~= 0 and AW_StackingDisabled[token] ~= true
end

local function guidKey(guid)
    if type(guid) ~= "string" then return nil end
    return string.upper((string.gsub(guid, "^0[xX]", "")))
end

function C_NamePlate.GetNamePlateForUnit(unit)
    if type(unit) ~= "string" then return nil end
    local plates = AW_NamePlates
    local plate = plates and plates[unit]
    if plate then return decorate(plate) end
    -- "target"/"focus" and friends have no token key: resolve them through the guid the client itself
    -- reports for that unit, which is the same link the token path uses.
    local key = guidKey(UnitGUID and UnitGUID(unit))
    local byGuid = AW_NamePlateGuids
    if key and byGuid then return decorate(byGuid[key]) end
    return nil
end

function C_NamePlate.GetNamePlates()
    local out = {}
    local list = AW_NamePlateList
    if type(list) == "table" then
        for i = 1, #list do out[i] = decorate(list[i]) end
    end
    return out
end

-- guid -> плейт / guid -> токен. У форка awesome это C-функции (GetNamePlateByGUID,
-- GetNamePlateTokenByGUID); у нас те же две связи лежат в данных dll -- AW_NamePlateGuids и
-- AW_NamePlateTokens, ключ hex без 0x в верхнем регистре, как его печатает UnitGUID().
function C_NamePlate.GetNamePlateByGUID(guid)
    local key = guidKey(guid)
    local byGuid = AW_NamePlateGuids
    if key and byGuid then return decorate(byGuid[key]) end
    return nil
end

function C_NamePlate.GetNamePlateTokenByGUID(guid)
    local key = guidKey(guid)
    local byToken = AW_NamePlateTokens
    if key and byToken then return byToken[key] end
    return nil
end
