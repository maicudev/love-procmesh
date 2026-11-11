-- utility functions for lists stored in Lua tables
local function lmap(t, f)
  local res = {};
  for i,v in ipairs(t) do res[i] = f(v); end
  return res;
end

local function lcopy(t)
  local t2 = {}
  for k,v in pairs(t) do t2[k] = v end
  return t2
end

local function lappend(t1, t2)
  local res = lcopy(t1)
  for i,v in ipairs(t2) do table.insert(res, v) end
  return res
end

local function lreverse(t)
  for i=1, math.floor(#t / 2) do
    t[i], t[#t - i + 1] = t[#t - i + 1], t[i]
  end
  return t
end

-- Constructive Solid Geometry (CSG) is a modeling technique that uses Boolean
-- operations like union and intersection to combine 3D solids. self.library
-- implements CSG operations on meshes elegantly and concisely using BSP trees,
-- and is meant to serve as an easily understandable implementation of the
-- algorithm. All edge cases involving overlapping coplanar polygons in both
-- solids are correctly handled.
-- 
-- Example usage:
-- 
--     local cube = CSG.cube()
--     local sphere = CSG.sphere({ radius: 1.3 })
--     local polygons = cube.subtract(sphere).toPolygons()
-- 
--
-- ## Implementation Details
-- 
-- All CSG operations are implemented in terms of two functions, `clipTo()` and
-- `invert()`, which remove parts of a BSP tree inside another BSP tree and swap
-- solid and empty space, respectively. To find the union of `a` and `b`, we
-- want to remove everything in `a` inside `b` and everything in `b` inside `a`,
-- then combine polygons from `a` and `b` into one solid:
-- 
--     a:clipTo(b)
--     b:clipTo(a)
--     a:build(b:allPolygons())
-- 
-- The only tricky part is handling overlapping coplanar polygons in both trees.
-- The code above keeps both copies, but we need to keep them in one tree and
-- remove them in the other tree. To remove them from `b` we can clip the
-- inverse of `b` against `a`. The code for union now looks like self.
-- 
--     a:clipTo(b)
--     b:clipTo(a)
--     b:invert()
--     b:clipTo(a)
--     b:invert()
--     a:build(b:allPolygons())
-- 
-- Subtraction and intersection naturally follow from set operations. If
-- union is `A | B`, subtraction is `A - B = ~(~A | B)` and intersection is
-- `A & B = ~(~A | ~B)` where `~` is the complement operator.
-- 
-- ## License
-- 
-- Copyright (c) 2011 Evan Wallace (http:--madebyevan.com/), under the MIT license.

local m = {}
local menori = require 'menori'
local vec3 = menori.ml.vec3
local normalize_polygons
local unpack = table.unpack or unpack

m.__index = m
m.__add = function (lhs, rhs) return lhs:union(rhs) end
m.__sub = function (lhs, rhs) return lhs:subtract(rhs) end
m.__mul = function (lhs, rhs) return lhs:intersect(rhs) end


local CSG = {}

--- Create an empty CSG primitive.
-- Holds a representation of triangle mesh that supports CSG manipulations,
-- inside a binary space partition tree. Two CSG primitives can be combined
-- using the `union()`, `subtract()`, and `intersect()` methods.
function m.new()
  local self = setmetatable({}, m)
  self.polygons = {}
  return self
end


-- Construct a CSG primitive from a list of `CSG.Polygon` instances.
function m.fromPolygons(polygons) 
  local self = m.new()
  self.polygons = polygons
  return self
end


--- Create CSG representation from a solid shape.
-- Solid is a table that stores vertices in nested table under key `vlist`,
-- and indices to triangle vertices in a flat table under key `ilist`.
function m.fromSolid(solid, shared)
  local self = m.new()
  for i = 1, #solid.ilist - 2, 3 do
    local v1 = solid.vlist[solid.ilist[i + 0]]
    local v2 = solid.vlist[solid.ilist[i + 1]]
    local v3 = solid.vlist[solid.ilist[i + 2]]
    local triangle = {
      m.Vertex.new(vec3(unpack(v1)), vec3(select(4, unpack(v1)))),
      m.Vertex.new(vec3(unpack(v2)), vec3(select(4, unpack(v2)))),
      m.Vertex.new(vec3(unpack(v3)), vec3(select(4, unpack(v3))))}
    table.insert(self.polygons, m.Polygon.new(triangle, shared))
  end
  return self
end


--- Create a copy of CSG object.
-- This is not needed for normal use as union/subtract/intersect operations
-- internally clone the input objects to keep them preserved.
function m:clone()
  local other = m.new()
  other.polygons = lmap(self.polygons, function(p) return p:clone() end)
  return other
end


function m:transform(transform)
  local transformed = {}
  for _, polygon in ipairs(self.polygons) do
    for _, v in ipairs(polygon.vertices) do
      if not transformed[v] then
        v.pos:set(transform:multiply_vec3(v.pos))
        transformed[v] = true
      end
    end
    polygon.plane = m.Plane.fromPoints(
      polygon.vertices[1].pos,
      polygon.vertices[2].pos,
      polygon.vertices[3].pos
    )
    for _, v in ipairs(polygon.vertices) do
      v.normal:set(polygon.plane.normal)
    end
  end
  return self
end


function m:toPolygons()
  return self.polygons
end


--- Create a CSG that covers volumes of both supplied CSG objects.
--     +-------+             +-------+
--     |       |             |       |
--     |   A   |             |       |
--     |    +--+----+   =>   |       +----+
--     +----+--+    |        +----+       |
--          |   B   |             |       |
--          |       |             |       |
--          +-------+             +-------+
function m:union(csg) 
  local a = m.Node.new(self:clone().polygons)
  local b = m.Node.new(csg:clone().polygons)
  a:clipTo(b)
  b:clipTo(a)
  b:invert()
  b:clipTo(a)
  b:invert()
  a:build(b:allPolygons())
  return m.fromPolygons(normalize_polygons(a:allPolygons()))
end


--- Create a CSG that subtracts volume of second CSG from the first CSG.
--     +-------+             +-------+
--     |       |             |       |
--     |   A   |             |       |
--     |    +--+----+   =>   |    +--+
--     +----+--+    |        +----+
--          |   B   |
--          |       |
--          +-------+
-- 
function m:subtract(csg)
  local a = m.Node.new(self:clone().polygons)
  local b = m.Node.new(csg:clone().polygons)
  a:invert()
  a:clipTo(b)
  b:clipTo(a)
  b:invert()
  b:clipTo(a)
  b:invert()
  a:build(b:allPolygons())
  a:invert()
  return m.fromPolygons(normalize_polygons(a:allPolygons()))
end


--- Create a CSG that covers only volume that both first and second CSG cover.
--     +-------+
--     |       |
--     |   A   |
--     |    +--+----+   =>   +--+
--     +----+--+    |        +--+
--          |   B   |
--          |       |
--          +-------+
-- 
function m:intersect(csg)
  local a = m.Node.new(self:clone().polygons)
  local b = m.Node.new(csg:clone().polygons)
  a:invert()
  b:clipTo(a)
  b:invert()
  a:clipTo(b)
  b:clipTo(a)
  a:build(b:allPolygons())
  a:invert()
  return m.fromPolygons(normalize_polygons(a:allPolygons()))
end


--- Return a CSG with solid and empty space inverted.
function m:inverse()
  local csg = self:clone()
  lmap(csg.polygons, function(p) p:flip() end)
  return csg
end


-- # class Vertex

-- Represents a vertex of a polygon. Use your own vertex class instead of this
-- one to provide additional features like texture coordinates and vertex
-- colors. Custom vertex classes need to provide a `pos` property and `clone()`,
-- `flip()`, and `interpolate()` methods that behave analogous to the ones
-- defined by `CSG.Vertex`. self.class provides `normal` so convenience
-- functions like `CSG.sphere()` can return a smooth vertex normal, but `normal`
-- is not used anywhere else.
m.Vertex = {}
m.Vertex.__index = m.Vertex

function m.Vertex.new(pos, normal)
  local self = setmetatable({}, m.Vertex)  
  self.pos = vec3(pos)
  self.normal = vec3(normal)
  return self
end


function m.Vertex:clone()
  return m.Vertex.new(self.pos, self.normal)
end


-- Invert all orientation-specific data (e.g. vertex normal). Called when the
-- orientation of a polygon is flipped.
function m.Vertex:flip()
  self.normal = -self.normal
end


-- Create a vertex between self.vertex and `other` by linearly
-- interpolating all properties using a parameter of `t`. Subclasses should
-- override self.to interpolate additional properties.
function m.Vertex:interpolate(other, t)
  return m.Vertex.new(
    vec3.lerp(self.pos, other.pos, t),
    vec3.lerp(self.normal, other.normal, t)
  )
end


-- # class Plane

-- Represents a plane in 3D space.
m.Plane = {
  EPSILON = 1e-5, -- tolerance used by `splitPolygon()` to decide if a point is on the plane
}
m.Plane.__index = m.Plane


function m.Plane.new(normal, w)
  local self = setmetatable({}, m.Plane)
  self.normal = vec3(normal)
  self.w = w
  return self
end


function m.Plane.fromPoints(a, b, c)
  local n = vec3.cross(b - a, c - a):normalize()
  return m.Plane.new(n, vec3.dot(n, a))
end


function m.Plane:clone()
    return m.Plane.new(self.normal, self.w)
end


function m.Plane:flip()
    self.normal = -self.normal
    self.w = -self.w
end


-- Split `polygon` by self.plane if needed, then put the polygon or polygon
-- fragments in the appropriate lists. Coplanar polygons go into either
-- `coplanarFront` or `coplanarBack` depending on their orientation with
-- respect to self.plane. Polygons in front or in back of self.plane go into
-- either `front` or `back`.
function m.Plane:splitPolygon(polygon, coplanarFront, coplanarBack, front, back)
    local COPLANAR = 0
    local FRONT = 1
    local BACK = 2
    local SPANNING = 3

  -- Classify each point as well as the entire polygon into one of the above
  -- four classes.
    local hasFront, hasBack = false, false
    local types = {}
    for i, v in ipairs(polygon.vertices) do
      local t = vec3.dot(self.normal, v.pos) - self.w
      local ptype = COPLANAR
      if (t < -m.Plane.EPSILON) then
        ptype = BACK
      elseif (t > m.Plane.EPSILON) then
        ptype = FRONT
      end
      hasFront = hasFront or ptype == FRONT
      hasBack = hasBack or ptype == BACK
      table.insert(types, ptype)
    end
    local polygonType = hasFront and hasBack and SPANNING
      or hasFront and FRONT
      or hasBack and BACK
      or COPLANAR

  -- Put the polygon in the correct list, splitting it when necessary.
    if(polygonType == COPLANAR) then
      if vec3.dot(self.normal, polygon.plane.normal) > 0 then
        table.insert(coplanarFront, polygon)
      else 
        table.insert(coplanarBack, polygon)
      end
    elseif(polygonType == FRONT) then
      table.insert(front, polygon)
    elseif(polygonType == BACK) then
      table.insert(back, polygon)
    elseif(polygonType == SPANNING) then
      local f = {}
      local b = {}
      for i, vi in ipairs(polygon.vertices) do
        local j = 1 + (i % #polygon.vertices)
        local ti = types[i]
        local tj = types[j]
        local vj = polygon.vertices[j]
        if (ti ~= BACK) then table.insert(f, vi) end
        if (ti ~= FRONT) then
          if (ti ~= BACK) then
            table.insert(b, vi:clone())
          else
            table.insert(b, vi)
          end
        end
        if ((ti == FRONT and tj == BACK) or (ti == BACK and tj == FRONT)) then
          local t = (self.w - vec3.dot(self.normal, vi.pos))
            / vec3.dot(self.normal, vj.pos - vi.pos)
          local v = vi:interpolate(vj, t)
          table.insert(f, v)
          table.insert(b, v:clone())
        end
      end
      if (#f >= 3) then table.insert(front, m.Polygon.new(f, polygon.shared)) end
      if (#b >= 3) then table.insert(back, m.Polygon.new(b, polygon.shared)) end
    end
end


-- # class Polygon

-- Represents a convex polygon. The vertices used to initialize a polygon must
-- be coplanar and form a convex loop. They do not have to be `CSG.Vertex`
-- instances but they must behave similarly (duck typing can be used for
-- customization).
-- 
-- Each convex polygon has a `shared` property, which is shared between all
-- polygons that are clones of each other or were split from the same polygon.
-- self.can be used to define per-polygon properties (such as surface color).
m.Polygon = {}
m.Polygon.__index = m.Polygon
function m.Polygon.new(vertices, shared)
  local self = setmetatable({}, m.Polygon)
  self.vertices = vertices
  self.shared = shared
  self.plane = m.Plane.fromPoints(vertices[1].pos, vertices[2].pos, vertices[3].pos)
  return self
end


function m.Polygon:clone()
  local vertices = lmap(self.vertices, function(v) return v:clone() end)
  return m.Polygon.new(vertices, self.shared)
end


function m.Polygon:flip()
  lmap(lreverse(self.vertices), function(v) v:flip() end)
  self.plane:flip()
end

local POLYGON_EPSILON = 1e-5

local function point_key(position)
  local function quantize(value)
    return math.floor(value / POLYGON_EPSILON + 0.5)
  end
  return string.format('%d,%d,%d',
    quantize(position.x), quantize(position.y), quantize(position.z))
end

local function clean_polygon(polygon)
  local vertices = {}
  for _, vertex in ipairs(polygon.vertices) do
    if #vertices == 0 or vec3.distance(vertices[#vertices].pos, vertex.pos) > POLYGON_EPSILON then
      vertices[#vertices + 1] = vertex:clone()
    end
  end
  if #vertices > 1 and vec3.distance(vertices[1].pos, vertices[#vertices].pos) <= POLYGON_EPSILON then
    table.remove(vertices)
  end

  local changed = true
  while changed and #vertices >= 3 do
    changed = false
    for i = 1, #vertices do
      local previous = vertices[(i - 2) % #vertices + 1].pos
      local current = vertices[i].pos
      local following = vertices[i % #vertices + 1].pos
      local first = current - previous
      local second = following - current
      local scale = math.max(first:length() * second:length(), 1)
      if vec3.cross(first, second):length() <= POLYGON_EPSILON * scale
          and vec3.dot(first, second) >= 0 then
        table.remove(vertices, i)
        changed = true
        break
      end
    end
  end

  if #vertices < 3 then
    return nil
  end
  return m.Polygon.new(vertices, polygon.shared)
end

local function merge_polygons(a, edge_a, b, edge_b)
  if vec3.dot(a.plane.normal, b.plane.normal) < 1 - POLYGON_EPSILON
      or math.abs(a.plane.w - b.plane.w) > POLYGON_EPSILON then
    return nil
  end

  local vertices = {}
  local count_a, count_b = #a.vertices, #b.vertices
  for offset = 1, count_a do
    vertices[#vertices + 1] = a.vertices[(edge_a + offset - 1) % count_a + 1]:clone()
  end
  for offset = 2, count_b - 1 do
    vertices[#vertices + 1] = b.vertices[(edge_b + offset - 1) % count_b + 1]:clone()
  end

  local cleaned = clean_polygon(m.Polygon.new(vertices, a.shared))
  if not cleaned then
    return nil
  end

  for i, vertex in ipairs(cleaned.vertices) do
    local previous = cleaned.vertices[(i - 2) % #cleaned.vertices + 1].pos
    local current = vertex.pos
    local following = cleaned.vertices[i % #cleaned.vertices + 1].pos
    local turn = vec3.cross(current - previous, following - current)
    if vec3.dot(turn, cleaned.plane.normal) < -POLYGON_EPSILON then
      return nil
    end
  end
  return cleaned
end

normalize_polygons = function(source)
  local polygons = {}
  for _, polygon in ipairs(source) do
    local cleaned = clean_polygon(polygon)
    if cleaned then
      polygons[#polygons + 1] = cleaned
    end
  end

  while true do
    local directed_edges = {}
    local merged = false
    for i, polygon in ipairs(polygons) do
      for edge = 1, #polygon.vertices do
        local next_edge = edge % #polygon.vertices + 1
        local first = point_key(polygon.vertices[edge].pos)
        local second = point_key(polygon.vertices[next_edge].pos)
        local forward = first .. '|' .. second
        local reverse = second .. '|' .. first
        local candidates = directed_edges[reverse]
        if candidates then
          for _, candidate in ipairs(candidates) do
            if candidate.polygon ~= i then
              local joined = merge_polygons(
                polygons[candidate.polygon], candidate.edge,
                polygon, edge)
              if joined then
                local remove_index = math.max(i, candidate.polygon)
                local keep_index = math.min(i, candidate.polygon)
                polygons[keep_index] = joined
                table.remove(polygons, remove_index)
                merged = true
                break
              end
            end
          end
        end
        if merged then break end
        local edges = directed_edges[forward] or {}
        edges[#edges + 1] = {polygon = i, edge = edge}
        directed_edges[forward] = edges
      end
      if merged then break end
    end
    if not merged then
      return polygons
    end
  end
end

--/ class Node --------------------------------------------------------------------------
-- Holds a node in a BSP tree. A BSP tree is built from a collection of polygons
-- by picking a polygon to split along. That polygon (and all other coplanar
-- polygons) are added directly to that node and the other polygons are added to
-- the front and/or back subtrees. This is not a leafy BSP tree since there is
-- no distinction between internal and leaf nodes.

m.Node = {}
m.Node.__index = m.Node


function m.Node.new(polygons)
  local self = setmetatable({}, m.Node)
  self.plane = nil
  self.front = nil
  self.back = nil
  self.polygons = {}
  if (polygons) then self:build(polygons) end
  return self
end


function m.Node:clone()
  local other = m.Node.new()
  other.plane = self.plane and self.plane:clone()
  other.front = self.front and self.front:clone()
  other.back = self.back and self.back:clone()
  other.polygons = lmap(self.polygons, function(p) return p:clone() end)
  return other
end


-- Convert solid space to empty space and empty space to solid space.
function m.Node:invert()
  for i, p in ipairs(self.polygons) do
    p:flip()
  end
  self.plane:flip()
  if (self.front) then self.front:invert() end
  if (self.back) then self.back:invert() end
  local temp = self.front
  self.front = self.back
  self.back = temp
end


-- Recursively remove all polygons in `polygons` that are inside self.BSP
-- tree.
function m.Node:clipPolygons(polygons)
    if (not self.plane) then return lcopy(polygons) end
    local front = {}
    local back = {}
    for i, p in ipairs(polygons) do
      self.plane:splitPolygon(p, front, back, front, back)
    end
    if (self.front) then front = self.front:clipPolygons(front) end
    if (self.back) then back = self.back:clipPolygons(back)
    else back = {} end
    return lappend(front, back)
end


-- Remove all polygons in self.BSP tree that are inside the other BSP tree
-- `bsp`.
function m.Node:clipTo(bsp)
    self.polygons = bsp:clipPolygons(self.polygons)
    if (self.front) then self.front:clipTo(bsp) end
    if (self.back) then self.back:clipTo(bsp) end
end


-- Return a list of all polygons in self.BSP tree.
function m.Node:allPolygons()
  local polygons = lcopy(self.polygons)
  if (self.front) then polygons = lappend(polygons, self.front:allPolygons()) end
  if (self.back) then polygons = lappend(polygons, self.back:allPolygons()) end
  return polygons
end


-- Build a BSP tree out of `polygons`. When called on an existing tree, the
-- polygons are filtered down to the bottom of the tree and become new
-- nodes there. Each set of polygons is partitioned using the first polygon
-- (no heuristic is used to pick a good split).
function m.Node:build(polygons, depth)
  depth = depth or 1
  if (#polygons == 0) then return end
  if (not self.plane) then self.plane = polygons[1].plane:clone() end
  local front = {}
  local back = {}
  for i, p in ipairs(polygons) do
    self.plane:splitPolygon(p, self.polygons, self.polygons, front, back)
  end
  if depth > 8000 then return end -- stack overflow protection
  if (#front > 0) then
    if (not self.front) then self.front = m.Node.new() end
    self.front:build(front, depth + 1)
  end
  if (#back > 0) then
    if (not self.back) then self.back = m.Node.new() end
    self.back:build(back, depth + 1)
  end
end


return m
