-- Small helpers on plain Lua values, shared by the pure modules and the pages.
local util = {}

-- The index of value in list, or nil.
function util.indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

-- n held between low and high.
function util.clamp(n, low, high)
  return math.max(low, math.min(high, n))
end

return util
