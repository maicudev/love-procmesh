local Vector3 = {}
local metatable = {}
metatable.__index = metatable

local function components(value, y, z)
  if type(value) == 'table' then
    return value.x or value[1] or 0, value.y or value[2] or 0, value.z or value[3] or 0
  end
  return value or 0, y or 0, z or 0
end

local function new(x, y, z)
  local self = setmetatable({}, metatable)
  self.x, self.y, self.z = components(x, y, z)
  return self
end

setmetatable(Vector3, {
  __call = function(_, ...)
    return new(...)
  end
})

function metatable.__index(self, key)
  if key == 1 then return rawget(self, 'x') end
  if key == 2 then return rawget(self, 'y') end
  if key == 3 then return rawget(self, 'z') end
  return Vector3[key]
end

function metatable.__newindex(self, key, value)
  if key == 1 then return rawset(self, 'x', value) end
  if key == 2 then return rawset(self, 'y', value) end
  if key == 3 then return rawset(self, 'z', value) end
  return rawset(self, key, value)
end

function metatable.__add(a, b)
  local ax, ay, az = components(a)
  local bx, by, bz = components(b)
  return new(ax + bx, ay + by, az + bz)
end

function metatable.__sub(a, b)
  local ax, ay, az = components(a)
  local bx, by, bz = components(b)
  return new(ax - bx, ay - by, az - bz)
end

function metatable.__mul(a, b)
  if type(a) == 'number' then a, b = b, a end
  local ax, ay, az = components(a)
  if type(b) == 'number' then
    return new(ax * b, ay * b, az * b)
  end
  local bx, by, bz = components(b)
  return new(ax * bx, ay * by, az * bz)
end

function metatable.__div(a, b)
  local ax, ay, az = components(a)
  if type(b) == 'number' then
    return new(ax / b, ay / b, az / b)
  end
  local bx, by, bz = components(b)
  return new(ax / bx, ay / by, az / bz)
end

function metatable.__unm(self)
  return new(-self.x, -self.y, -self.z)
end

function metatable.__tostring(self)
  return string.format('(%g, %g, %g)', self.x, self.y, self.z)
end

function Vector3:set(x, y, z)
  self.x, self.y, self.z = components(x, y, z)
  return self
end

function Vector3:unpack()
  return self.x, self.y, self.z
end

function Vector3:add(x, y, z)
  local ax, ay, az = components(self)
  local bx, by, bz = components(x, y, z)
  self.x, self.y, self.z = ax + bx, ay + by, az + bz
  return self
end

function Vector3:sub(x, y, z)
  local ax, ay, az = components(self)
  local bx, by, bz = components(x, y, z)
  self.x, self.y, self.z = ax - bx, ay - by, az - bz
  return self
end

function Vector3:mul(x, y, z)
  local ax, ay, az = components(self)
  if type(x) == 'number' and y == nil then
    self.x, self.y, self.z = ax * x, ay * x, az * x
  else
    local bx, by, bz = components(x, y, z)
    self.x, self.y, self.z = ax * bx, ay * by, az * bz
  end
  return self
end

function Vector3:dot(x, y, z)
  local bx, by, bz = components(x, y, z)
  return self.x * bx + self.y * by + self.z * bz
end

function Vector3:cross(other)
  local x = self.y * other.z - self.z * other.y
  local y = self.z * other.x - self.x * other.z
  local z = self.x * other.y - self.y * other.x
  self.x, self.y, self.z = x, y, z
  return self
end

function Vector3:length()
  return math.sqrt(self:dot(self))
end

function Vector3:normalize()
  local length = self:length()
  if length > 0 then self:mul(1 / length) end
  return self
end

function Vector3:distance(other)
  local x, y, z = self.x - other.x, self.y - other.y, self.z - other.z
  return math.sqrt(x * x + y * y + z * z)
end

function Vector3:lerp(other, t)
  self.x = self.x + (other.x - self.x) * t
  self.y = self.y + (other.y - self.y) * t
  self.z = self.z + (other.z - self.z) * t
  return self
end

return Vector3
