--[[
   Pure Lua implementation of the 'bit' library (LuaBitOp).
   This is a fallback for environments where the native bit library is missing.
   Note: This implementation is slower than the C/JIT version but ensures compatibility.
]] local bit = {}

local function tobit(x)
    x = x or 0
    if x >= -2147483648 and x <= 2147483647 then
        return x
    end
    return (x % 4294967296 + 2147483648) % 4294967296 - 2147483648
end
bit.tobit = tobit

function bit.tohex(x, n)
    n = n or 8
    local up
    if n <= 0 then
        if n == 0 then
            return ""
        end
        up = true
        n = -n
    end
    x = tobit(x)
    if x < 0 then
        x = x + 4294967296
    end
    local s = string.format("%x", x)
    if #s < n then
        s = string.rep("0", n - #s) .. s
    elseif #s > n then
        s = string.sub(s, -n)
    end
    if up then
        return string.upper(s)
    end
    return s
end

function bit.bnot(x)
    return tobit(-1 - x)
end

local function band2(a, b)
    local p = 1
    local res = 0
    a = tobit(a)
    b = tobit(b)
    if a < 0 then
        a = a + 4294967296
    end
    if b < 0 then
        b = b + 4294967296
    end
    while a > 0 and b > 0 do
        local ra = a % 2
        local rb = b % 2
        if ra == 1 and rb == 1 then
            res = res + p
        end
        a = (a - ra) / 2
        b = (b - rb) / 2
        p = p * 2
    end
    return tobit(res)
end

function bit.band(...)
    local args = {...}
    if #args == 0 then
        return 0
    end
    local res = args[1]
    for i = 2, #args do
        res = band2(res, args[i])
    end
    return res
end

local function bor2(a, b)
    local p = 1
    local res = 0
    a = tobit(a)
    b = tobit(b)
    if a < 0 then
        a = a + 4294967296
    end
    if b < 0 then
        b = b + 4294967296
    end
    while a > 0 or b > 0 do
        local ra = a % 2
        local rb = b % 2
        if ra == 1 or rb == 1 then
            res = res + p
        end
        a = (a - ra) / 2
        b = (b - rb) / 2
        p = p * 2
    end
    return tobit(res)
end

function bit.bor(...)
    local args = {...}
    if #args == 0 then
        return 0
    end
    local res = args[1]
    for i = 2, #args do
        res = bor2(res, args[i])
    end
    return res
end

local function bxor2(a, b)
    local p = 1
    local res = 0
    a = tobit(a)
    b = tobit(b)
    if a < 0 then
        a = a + 4294967296
    end
    if b < 0 then
        b = b + 4294967296
    end
    while a > 0 or b > 0 do
        local ra = a % 2
        local rb = b % 2
        if ra ~= rb then
            res = res + p
        end
        a = (a - ra) / 2
        b = (b - rb) / 2
        p = p * 2
    end
    return tobit(res)
end

function bit.bxor(...)
    local args = {...}
    if #args == 0 then
        return 0
    end
    local res = args[1]
    for i = 2, #args do
        res = bxor2(res, args[i])
    end
    return res
end

function bit.lshift(x, n)
    x = tobit(x)
    n = n % 32
    if n == 0 then
        return x
    end
    return tobit(x * (2 ^ n))
end

function bit.rshift(x, n)
    x = tobit(x)
    if x < 0 then
        x = x + 4294967296
    end
    n = n % 32
    if n == 0 then
        return tobit(x)
    end
    return tobit(math.floor(x / (2 ^ n)))
end

function bit.arshift(x, n)
    x = tobit(x)
    n = n % 32
    if n == 0 then
        return x
    end
    if x >= 0 then
        return tobit(math.floor(x / (2 ^ n)))
    else
        return tobit(math.floor(x / (2 ^ n)) + (2 ^ 32 - 2 ^ (32 - n))) -- Not exactly correct for arithmetic shift of negative?
        -- Actually, for Lua 5.1/standard bit lib behavior:
        -- arshift preserves sign.
    end
    -- Correct implementation for arshift:
    if n == 0 then
        return x
    end
    local shift = 2 ^ n
    if x >= 0 then
        return math.floor(x / shift)
    else
        -- x is negative. 
        -- Example: -2 (0xFFFFFFFE) >> 1 should be -1 (0xFFFFFFFF)
        -- In unsigned: 4294967294 / 2 = 2147483647 (0x7FFFFFFF) -> this is logical shift
        -- We need to fill with 1s.
        -- return math.floor(x / shift) in Lua implies float division floor.
        -- -2 / 2 = -1. Correct.
        -- -4 / 2 = -2.
        -- -5 / 2 = -2.5 -> floor -> -3.
        -- Wait, arshift of -5 >> 1 is:
        -- 111...1011 >> 1 = 111...1101 (-3). 
        -- So math.floor(x / 2^n) seems correct for negative numbers in 2's complement view IF x was passed as number?
        -- Lua numbers are doubles.
        return math.floor(x / shift)
    end
end
-- Re-implement arshift simpler:
function bit.arshift(x, n)
    x = tobit(x)
    n = n % 32
    if n == 0 then
        return x
    end
    return math.floor(x / (2 ^ n))
end

function bit.rol(x, n)
    return bit.bor(bit.lshift(x, n), bit.rshift(x, 32 - n))
end

function bit.ror(x, n)
    return bit.bor(bit.rshift(x, n), bit.lshift(x, 32 - n))
end

function bit.bswap(x)
    x = tobit(x)
    local a = bit.band(x, 0xff)
    local b = bit.band(bit.rshift(x, 8), 0xff)
    local c = bit.band(bit.rshift(x, 16), 0xff)
    local d = bit.band(bit.rshift(x, 24), 0xff)
    return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
end

-- Expose to global environment to match LuaJIT/C bit library behavior
_G.bit = bit

return bit
