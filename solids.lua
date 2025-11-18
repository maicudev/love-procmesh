-- Solids library creates and manipulates the triangle meshes
-- The "solid" here refers to a triangle mesh stored in a table:
--  {
--    vlist = { {0,0,0,_}, {1,2,3,_}, _} -- list of vertices storing data (positions, normals, colors...)
--    ilist = {1, 2, 3, _},              -- flat list of indices; each triplet forms a triangle
--    sides = {top = {1, 2, 3, _}, _}    -- shape sides mapped to the list of indices
--    vbuffer = Buffer(),                -- vertex buffer object for rendering, regenerated as needed
--    ibuffer = Buffer(),                -- index buffer object for rendering, regenerated as needed
--  }, with metatable accessors to manipulating functions.

local m = {}
m.__index = m

m.vbuffer_format = {
  { 'VertexPosition', 'vec3' },
  { 'VertexNormal',   'vec3' },
  { 'VertexColor',    'vec4' },
}

local EPSILON = 1e-6

local function listappend(t1, t2) -- mutates t1 in place
  for _,v in ipairs(t2) do
    table.insert(t1, v)
  end
  return t1
end


local function shuffle(list) -- shuffles a copy of a table list
  local shuffled = listappend({}, list)
  for i = 1, #shuffled do
    local j = lovr.math.random(1, #shuffled)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end
  return shuffled
end


-- to use integer pairs/triples as table keys, first convert them to a string
local function listToHash(...)   -- listToHash(1,2,3) -> '1;2;3'
  return table.concat({...}, ',')
end


-- round up passed-in numbers to specified precision and turn to string
local function precisionHash(precision, ...)
  local values = {...}
  for i, value in ipairs(values) do
    values[i] = math.floor(value / precision + 0.5) + 0.0
  end
  return table.concat(values, ';')
end


local function hashToList(s)     -- hashToList('1;2;3') -> 1, 2, 3
  local res = {}
  for str in string.gmatch(s, "([^,]+)") do
    table.insert(res, tonumber(str))
  end
  return unpack(res)
end


--- Sets future buffer format fields; best called upfront on init
-- existing solids need to be invalidated manually, for example by replacing them with :clone()
function m.setFormats(vertex_format, index_format)
  m.vbuffer_format = vertex_format or m.vbuffer_format
  m.ibuffer_format = index_format or m.ibuffer_format
end


--- Distance of a point vector from a line segment formed from two vectors
function m.linePointDistance(line, point)
  local segment = (line[2] - line[1]):normalize()
  -- old: segment:mul(dot) -> new immutable
  local proj = segment * (segment:dot(point - line[1]))
  return proj:distance(point)
end


--- Distance of a point vector from a triangle formed from three vectors
-- if positive, the point is in front of the triangle
-- if zero, point and triangle are coplanar
-- if negative, the point is behind the triangle
function m.trianglePointDistance(triangle, point)
  local ux = triangle[2][1] - triangle[1][1]
  local uy = triangle[2][2] - triangle[1][2]
  local uz = triangle[2][3] - triangle[1][3]
  local vx = triangle[3][1] - triangle[1][1]
  local vy = triangle[3][2] - triangle[1][2]
  local vz = triangle[3][3] - triangle[1][3]
  local cx = uy * vz - uz * vy
  local cy = uz * vx - ux * vz
  local cz = ux * vy - uy * vx
  local dx = point[1] - triangle[1][1]
  local dy = point[2] - triangle[1][2]
  local dz = point[3] - triangle[1][3]
  return cx * dx + cy * dy + cz * dz
end


function m.barycentric(triangle, point)
  local AB = {triangle[2][1] - triangle[1][1], triangle[2][2] - triangle[1][2], triangle[2][3] - triangle[1][3]}
  local AC = {triangle[3][1] - triangle[1][1], triangle[3][2] - triangle[1][2], triangle[3][3] - triangle[1][3]}
  local AP = {point[1] - triangle[1][1], point[2] - triangle[1][2], point[3] - triangle[1][3]}
  local dotABAB = AB[1]*AB[1] + AB[2]*AB[2] + AB[3]*AB[3]
  local dotACAC = AC[1]*AC[1] + AC[2]*AC[2] + AC[3]*AC[3]
  local dotABAC = AB[1]*AC[1] + AB[2]*AC[2] + AB[3]*AC[3]
  local dotABAP = AB[1]*AP[1] + AB[2]*AP[2] + AB[3]*AP[3]
  local dotACAP = AC[1]*AP[1] + AC[2]*AP[2] + AC[3]*AP[3]
  local denom = dotABAB * dotACAC - dotABAC * dotABAC
  if (denom == 0) then
      return nil -- degenerate triangle
  end
  local u = (dotACAC * dotABAP - dotABAC * dotACAP) / denom
  local v = (dotABAB * dotACAP - dotABAC * dotABAP) / denom
  local coords = {1 - u - v, u, v}
  local reconstructed = vector(
    coords[1] * triangle[1][1] + coords[2] * triangle[2][1] + coords[3] * triangle[3][1],
    coords[1] * triangle[1][2] + coords[2] * triangle[2][2] + coords[3] * triangle[3][2],
    coords[1] * triangle[1][3] + coords[2] * triangle[2][3] + coords[3] * triangle[3][3])
  if reconstructed:distance(point) < EPSILON then
    return coords
  else
    return nil -- point is not on triangle plane
  end
end


--- Cast a ray and return list of intersection points with the solid
-- uses Möller-Trumbore algorithm
function m:raycast(start, stop, doublesided)
  if self.normals_dirty then self:updateNormals() end
  local intersections = {}
  local dir = stop - start
  for i = 1, #self.ilist, 3 do
    local i1, i2, i3 = self.ilist[i], self.ilist[i+1], self.ilist[i+2]
    local a = vector(unpack(self.vlist[i1]))
    local b = vector(unpack(self.vlist[i2]))
    local c = vector(unpack(self.vlist[i3]))
    if doublesided or dir:dot(self.vlist[i1][4], self.vlist[i1][5], self.vlist[i1][6]) <= 0 then
      local edge1 = b - a
      local edge2 = c - a
      local h = vector(dir):cross(edge2)
      local par = edge1:dot(h)
      if par <= -EPSILON or par >= EPSILON then -- check if the ray and triangle are parallel
        local f = 1 / par
        local s = start - a
        local u = f * s:dot(h)
        if u >= 0 and u <= 1 then -- else intersection falls outside the triangle
          local q = s:cross(edge1)
          local v = f * dir:dot(q)
          if v >= 0 and u + v <= 1 then -- else intersection falls outside the triangle
            local t = f * edge2:dot(q)
            if t > EPSILON and t < 1 then -- check if intersection behind the start point
              local point = start + dir * t
              table.insert(intersections, point)
            end
          end
        end
      end
    end
  end
  return intersections
end


function m:centerOfMass()
  local center = vector(0, 0, 0)
  for i = 1, #self.vlist do
    center = center + vector(self.vlist[i][1], self.vlist[i][2], self.vlist[i][3])
  end
  center = center / #self.vlist
  return center
end


function m:volume()
  local total_volume = 0
  local centroid = self:centerOfMass()
  for i = 1, #self.ilist, 3 do
    local v1 = vector(self.vlist[self.ilist[i    ]][1], self.vlist[self.ilist[i    ]][2], self.vlist[self.ilist[i    ]][3]) - centroid
    local v2 = vector(self.vlist[self.ilist[i + 1]][1], self.vlist[self.ilist[i + 1]][2], self.vlist[self.ilist[i + 1]][3]) - centroid
    local v3 = vector(self.vlist[self.ilist[i + 2]][1], self.vlist[self.ilist[i + 2]][2], self.vlist[self.ilist[i + 2]][3]) - centroid
    local volume = math.abs(v1:dot(v2:cross(v3)) / 6)
    total_volume = total_volume + volume
  end
  return total_volume
end


--- Get a string with basic info about solid
function m:info()
  return string.format('Solid: %d vertices and %d indices; volume: %.2f, center-of-mass: (%g,%g,%g)',
    #self.vlist,
    #self.ilist,
    self:volume(),
    (self:centerOfMass()).x, (self:centerOfMass()).y, (self:centerOfMass()).z)
end


--- Create solid from existing using a user fn to process each vertex.
-- Preserves all the non-modified vertex information (for example colors).
--    modified_solid = solid_obj:map(function(x,y,z, ...)
--        -- manipulate x,y,z as needed
--        return x, y, z
--      end)
function m:map(fn, side_filter)
  local other = m.new()
  if side_filter then
    for i, vertex in ipairs(self.vlist) do
      other.vlist[i] = {unpack(vertex)}
    end
    for _, i in ipairs(side_filter) do
      local retvals = { fn(unpack(self.vlist[i])) }
      for j, val in ipairs(retvals) do
        other.vlist[i][j] = val
      end
    end
  else
    for i, v in ipairs(self.vlist) do
      other.vlist[i] = { fn(unpack(v)) }
      listappend(other.vlist[i], {select(#other.vlist[i] + 1, unpack(v))})
    end
  end
  for i, index in ipairs(self.ilist) do
    other.ilist[i] = index
  end
  for side, ilist in pairs(self.sides) do
    other.sides[side] = {}
    for i, index in ipairs(ilist) do
      other.sides[side][i] = index
    end
  end
  return other
end


--- Create a solid by transforming each vertex by mat4.
-- Example for laying down an upright mesh:
--    solid:transform(mat4():rotate(pi/2, 1,0,0))
function m:transform(transform, side_filter)
  return self:map(function(x, y, z)
    local p = transform * vector(x, y, z)
    return p.x, p.y, p.z
  end, side_filter)
end


function m:scale(vector_or_sx, sy, sz)
  local sx
  if type(vector_or_x) == 'table' then
    sx, sy, sz = vector_or_x.x, vector_or_x.y, vector_or_x.z
  elseif type(vector_or_sx) == 'number' then
    sx = vector_or_sx
    sy = sy or sx
    sz = sz or sy
  else
    error('unsupported input')
  end
  return self:map(function(x, y, z)
    return x * sx, y * sy, z * sz
  end)
end


-- distort the solid from reference curve shape to target curve shape
function m:bendOnCurve(curve_ref, curve_tgt, up, curve_subdivisions)
  up = up or vector(0, 1, 0)
  curve_subdivisions = curve_subdivisions or 32
  local solid = self:clone()
  local rendered_ref = curve_ref:render(curve_subdivisions)
  local points_ref = {}
  local usedIndexSet = {}
  local ts = {}
  for i = 1, #rendered_ref, 3 do
    table.insert(points_ref, vector(rendered_ref[i], rendered_ref[i + 1], rendered_ref[i + 2]))
  end
  local rendered_tgt = curve_tgt:render(curve_subdivisions)
  local points_tgt = {}
  for i = 1, #rendered_tgt, 3 do
    table.insert(points_tgt, vector(rendered_tgt[i], rendered_tgt[i + 1], rendered_tgt[i + 2]))
  end
  -- map mesh vertices to closest ref curve points
  local curveIndexFromMesh = {}
  for i, vn in ipairs(solid.vlist) do
    ts[i] = i / #solid.vlist
    local v = vector(unpack(vn))
    local shortest = math.huge
    local shortest_i
    for j, point in ipairs(points_ref) do
      local d = point:distance(v)
      if d < shortest then
        shortest = d
        shortest_i = j
      end
    end
    curveIndexFromMesh[vn] = shortest_i
    usedIndexSet[shortest_i] = true
  end
  -- calcualte transforms from ref curve to tgt curve
  local curveTransforms = {}
  for i = 1, #points_ref do
    if usedIndexSet[i] then
      local p_ref = points_ref[i]
      local p_tgt = points_tgt[i]
      local t_tgt = mat4():target(
        p_tgt,
        p_tgt + vector(curve_tgt:getTangent(ts[i])),
        up)
      local t_ref = mat4():target(
        p_ref,
        p_ref + vector(curve_ref:getTangent(ts[i])),
        up)
      curveTransforms[i] = t_tgt:mul(t_ref:invert())
    end
  end
  -- apply nearest transfrom to each vertex
  for i, vn in ipairs(solid.vlist) do
    local nearestT = curveTransforms[curveIndexFromMesh[vn]]
    local v = vector(unpack(vn))
    v = nearestT * v
    vn[1], vn[2], vn[3] = v.x, v.y, v.z
  end
  return solid
end


--- Bakes the additional data into all the vertex
-- Assumes that the first 6 vertex data are position and normal
-- Any other vertex data (material information, baked lighting) would go after and can be modified
-- This function applies same data to all the vertices
function m:bakeFill(...)
  if self.normals_dirty then self:updateNormals() end
  local vertex_attributes = {...}
  return self:map(function(...)
    local v = {...}
    local l = #v
    for i, vertex_attribute in ipairs(vertex_attributes) do
      v[l + i] = vertex_attribute
    end
    return unpack(v)
  end)
end


function m:setColor(r_or_table_or_vec, g, b, a)
  local r
  if getmetatable(r_or_table_or_vec) == getmetatable(vector.up) then
    r, g, b, a = r_or_table_or_vec.x, r_or_table_or_vec.y, r_or_table_or_vec.z, r_or_table_or_vec.w
  elseif type(r_or_table_or_vec) == 'table' then
    r, g, b, a = r_or_table_or_vec[1], r_or_table_or_vec[2], r_or_table_or_vec[3], r_or_table_or_vec[4]
  elseif type(r_or_table_or_vec) == 'number' then
    r = r_or_table_or_vec
    g = g or r
    b = b or g
  else
    error(string.format(
      'unsupported %s; use setColor(r, g, b) or setColor({r, g, b}) or setColor(vector(r, g, b))',
      type(r_or_table_or_vec)))
  end
  a = a or 1
  r, g, b = lovr.math.gammaToLinear(r, g, b)
  return self:map(function(...)
    local x, y, z, nx, ny, nz = ...
    nx, ny, nz = nx or 0, ny or 0, nz or 0
    return x, y, z, nx, ny, nz, r, g, b, a
  end)
end


function m:makeOutline(amount, color)
  amount = amount or 0.03
  color = color or { 0.1, 0.1, 0.1 }
  if self.normals_dirty then self:updateNormals() end
  precision = amount * 0.25
  local outline = m.new()
  local groups = {}         -- hash -> { vertexIndices... }
  for i = 1, #self.ilist, 3 do
    local i1, i2, i3 = self.ilist[i], self.ilist[i + 1], self.ilist[i + 2]
    local v1, v2, v3 = self.vlist[i1], self.vlist[i2], self.vlist[i3]
    local a = vector(v1[1], v1[2], v1[3])
    local b = vector(v2[1], v2[2], v2[3])
    local c = vector(v3[1], v3[2], v3[3])
    local n = (b - a):cross(c - a):normalize()
    local pa = a + n * amount
    local pb = b + n * amount
    local pc = c + n * amount
    local ia = #outline.vlist + 1
    table.insert(outline.vlist, { pa.x, pa.y, pa.z, -n.x, -n.y, -n.z })
    local ib = #outline.vlist + 1
    table.insert(outline.vlist, { pb.x, pb.y, pb.z, -n.x, -n.y, -n.z })
    local ic = #outline.vlist + 1
    table.insert(outline.vlist, { pc.x, pc.y, pc.z, -n.x, -n.y, -n.z })
    table.insert(outline.ilist, ib)
    table.insert(outline.ilist, ia)
    table.insert(outline.ilist, ic)
    local ha = precisionHash(precision, a.x, a.y, a.z)
    local hb = precisionHash(precision, b.x, b.y, b.z)
    local hc = precisionHash(precision, c.x, c.y, c.z)
    groups[ha] = groups[ha] or {}; table.insert(groups[ha], ia)
    groups[hb] = groups[hb] or {}; table.insert(groups[hb], ib)
    groups[hc] = groups[hc] or {}; table.insert(groups[hc], ic)
  end
  for _, groupH in pairs(groups) do
    local acc = vector(0, 0, 0)
    for _, vi in ipairs(groupH) do
      local v = outline.vlist[vi]
      acc = acc + vector(v[1], v[2], v[3])
    end
    local mean = acc * (1 / #groupH)
    for _, vi in ipairs(groupH) do
      local v = outline.vlist[vi]
      v[1], v[2], v[3] = mean.x, mean.y, mean.z
    end
  end
  outline.normals_dirty = false
  outline = outline:setColor(color)
  return outline
end


---  Adds an outline (scaled‐up, face-winding reversed, coloured) to the solid.
--  Returns same solid that contains the original solid and the outline.
function m:addOutline(amount, color)
  return self:makeOutline(amount, color):mergeIn({ self })
end


--- Create solid with no vertices shared between the two faces
function m:separateFaces()
  local other = m.fromVertices(self.vlist, self.ilist)
  local visited = {}
  for i, index in ipairs(other.ilist) do
    if visited[index] then
      local new_index = #other.vlist + 1
      other.vlist[new_index] = {unpack(self.vlist[index])}
      other.ilist[i] = new_index
    end
    visited[index] = true
  end
  return other
end


--- Identify triangles facing same way, merge into polygons
-- Returns faces, which is a list of lists of indices
function m:mergeTrianglesIntoPolygons(precision)
  precision = precision or 0.01
  if not self.ilist then return {} end
  -- build a mapping from a vertex to adjacent triangle indices
  local triangleFromVertex = {}
  for i = 1, #self.ilist, 3 do
    local vertexIndex = self.ilist[i + 0]
    triangleFromVertex[vertexIndex] = triangleFromVertex[vertexIndex] or {}
    table.insert(triangleFromVertex[vertexIndex], i)
    vertexIndex = self.ilist[i + 1]
    triangleFromVertex[vertexIndex] = triangleFromVertex[vertexIndex] or {}
    table.insert(triangleFromVertex[vertexIndex], i)
    vertexIndex = self.ilist[i + 2]
    triangleFromVertex[vertexIndex] = triangleFromVertex[vertexIndex] or {}
    table.insert(triangleFromVertex[vertexIndex], i)
  end
  -- calculate triangle normals and keep mapping from triangle index to its normal
  local normals = {}
  for i = 1, #self.ilist, 3 do
    local vi1, vi2, vi3 = self.ilist[i], self.ilist[i + 1], self.ilist[i + 2]
    local v1 = vector(unpack(self.vlist[vi1]))
    local v2 = vector(unpack(self.vlist[vi2]))
    local v3 = vector(unpack(self.vlist[vi3]))
    normals[i] = (v2 - v1):cross(v3 - v1):normalize()
  end
  -- merge adjacent triangles with same normals into faces
  local visited = {}
  local faces = {}
  for i = 1, #self.ilist, 3 do
    if not visited[i] then
      visited[i] = true
      local face = {self.ilist[i], self.ilist[i + 1], self.ilist[i + 2]}
      local stack = {i}
      while #stack > 0 do
        local tri = table.remove(stack)
        local n = normals[tri]
        local hash = precisionHash(precision, n.x, n.y, n.z)
        face.normal = vector(n)
        -- find all adjacent triangles which are not visited and have same normal
        for j = 0, 2 do
          local vertexIndex = self.ilist[tri + j]
          for _, adjacentTri in ipairs(triangleFromVertex[vertexIndex]) do
            if not visited[adjacentTri] then
              local an = normals[adjacentTri]
              local adjhash = precisionHash(precision, an.x, an.y, an.z)
              if adjhash == hash then
                table.insert(face, self.ilist[adjacentTri])
                table.insert(face, self.ilist[adjacentTri + 1])
                table.insert(face, self.ilist[adjacentTri + 2])
                visited[adjacentTri] = true
                table.insert(stack, adjacentTri)
              end
            end
          end
        end
      end
      table.insert(faces, face)
    end
  end
  return faces
end


--- Create solid with flipped vertex order.
function m:flipWinding()
  local other = self:clone()
  for i = 1, #other.ilist, 3 do
    other.ilist[i + 1], other.ilist[i + 2] = other.ilist[i + 2], other.ilist[i + 1]
  end
  return other
end


--- Create solid with x4 the geometry by subdividing each triangle.
function m:subdivide()
  local function halfway(p1, p2)
    local v = {}
    if p1[1] and p2[1] then
      v[1], v[2], v[3] = (p1[1] + p2[1]) / 2, (p1[2] + p2[2]) / 2, (p1[3] + p2[3]) / 2
    end
    if p1[4] and p2[4] then
      v[4], v[5], v[6] = (p1[4] + p2[4]) / 2, (p1[5] + p2[5]) / 2, (p1[6] + p2[6]) / 2
    end
    if p1[7] and p2[7] then
      v[7], v[8], v[9] = (p1[7] + p2[7]) / 2, (p1[8] + p2[8]) / 2, (p1[9] + p2[9]) / 2
    end
    return v
  end
  local other = self.new()
  local vertices = {}
  local indices = {}
  for i = 1, #self.ilist, 3 do
    local i1, i2, i3 = self.ilist[i + 0], self.ilist[i + 1], self.ilist[i + 2]
    local va, vb, vc = self.vlist[i1], self.vlist[i2], self.vlist[i3]
    local vab = halfway(va, vb)
    local vbc = halfway(vb, vc)
    local vca = halfway(vc, va)
    listappend(vertices, {va, vab, vca})
    listappend(indices, {#vertices - 2, #vertices - 1, #vertices})
    listappend(vertices, {vab, vb, vbc})
    listappend(indices, {#vertices - 2, #vertices - 1, #vertices})
    listappend(vertices, {vbc, vc, vca})
    listappend(indices, {#vertices - 2, #vertices - 1, #vertices})
    listappend(vertices, {vab, vbc, vca})
    listappend(indices, {#vertices - 2, #vertices - 1, #vertices})
  end
  other.vlist = vertices
  other.ilist = indices
  return other
end


-- remove degenerate triangles
function m:clean()
  local function is_degenerate(v1, v2, v3)
    local vec1 = vector(v2[1] - v1[1], v2[2] - v1[2], v2[3] - v1[3])
    local vec2 = vector(v3[1] - v1[1], v3[2] - v1[2], v3[3] - v1[3])
    local cross_product = vec1:cross(vec2)
    return cross_product:length() < 1e-6
  end
  local new_vertices = {}
  local new_indices = {}

  for _, vertex in ipairs(self.vlist) do
    table.insert(new_vertices, vertex)
  end


  local indices = self.ilist
  for i = 1, #indices, 3 do
    local v1_index = indices[i]
    local v2_index = indices[i + 1]
    local v3_index = indices[i + 2]
    local v1 = new_vertices[v1_index]
    local v2 = new_vertices[v2_index]
    local v3 = new_vertices[v3_index]
    if not is_degenerate(v1, v2, v3) then
      table.insert(new_indices, v1_index)
      table.insert(new_indices, v2_index)
      table.insert(new_indices, v3_index)
    end
  end
  return m.fromVertices(new_vertices, new_indices)
end


--- Converts flat list of triangle indices to flat list of line indices.
function m:triangleToLine(threshold)
  threshold = threshold or 0
  self:updateNormals()
  local line_pairs = {}

  local function calculateNormal(i1, i2, i3)
    local v1 = vector(self.vlist[i1][1], self.vlist[i1][2], self.vlist[i1][3])
    local v2 = vector(self.vlist[i2][1], self.vlist[i2][2], self.vlist[i2][3])
    local v3 = vector(self.vlist[i3][1], self.vlist[i3][2], self.vlist[i3][3])
    local edge1 = v2 - v1
    local edge2 = v3 - v1
    return edge1:cross(edge2):normalize()
  end


  local function listToHash(i1, i2)
    return math.min(i1, i2) * 1000000 + math.max(i1, i2)
  end


  for i = 1, #self.ilist, 3 do
    local i1, i2, i3 = self.ilist[i], self.ilist[i+1], self.ilist[i+2]
    local normal = calculateNormal(i1, i2, i3)

    line_pairs[listToHash(i1, i2)] = {i1, i2, normal}
    line_pairs[listToHash(i2, i3)] = {i2, i3, normal}
    line_pairs[listToHash(i3, i1)] = {i3, i1, normal}
  end


  local function calculateAngle(normal1, normal2)
    local dot_product = normal1:dot(normal2)
    dot_product = math.max(-1, math.min(1, dot_product))
    return math.acos(dot_product)
  end


  local line_indices = {}

  for hash, line_pair in pairs(line_pairs) do
    local i1, i2, normal1 = line_pair[1], line_pair[2], line_pair[3]
    local shared = false

    for other_hash, other_line_pair in pairs(line_pairs) do
      if other_hash ~= hash then
        local other_i1, other_i2, normal2 = other_line_pair[1], other_line_pair[2], other_line_pair[3]
        if (other_i1 == i1 and other_i2 == i2) or (other_i1 == i2 and other_i2 == i1) then
          local angle = calculateAngle(normal1, normal2)
          if angle >= threshold then
            table.insert(line_indices, i1)
            table.insert(line_indices, i2)
          end
          shared = true
          break
        end
      end
    end


    if not shared then
      table.insert(line_indices, i1)
      table.insert(line_indices, i2)
    end
  end


  local other = self:clone()
  other.ilist = line_indices
  other:refresh()
  other.mesh:setDrawMode('lines')
  return other
end


--- Combine triangles from two or more solids into a merged solid.
function m.merge(solidsList)
  local other = m.new()
  other.normals_dirty = false
  for _, another in ipairs(solidsList) do
    local offset = #other.vlist
    listappend(other.vlist, another.vlist)
    for _, index in ipairs(another.ilist) do
      table.insert(other.ilist, index + offset)
    end
    other.normals_dirty = other.normals_dirty or another.normals_dirty
  end
  return other
end


function m:mergeIn(solid_or_list)
  assert(type(solid_or_list) == 'table', 'mergeIn works only on solid or {} list of solids')
  if solid_or_list.mergeIn then
    solid_or_list = { solid_or_list }
  end
  for _, another in ipairs(solid_or_list) do
    local offset = #self.vlist
    listappend(self.vlist, another.vlist)
    for _, index in ipairs(another.ilist) do
      table.insert(self.ilist, index + offset)
    end
    self.normals_dirty = self.normals_dirty or self.normals_dirty
  end
  return self
end


--- Retrieves a map of connections between vertex indices in a solid.
function m:getConnections()
  local graph = {}
  for i = 1, #self.ilist, 3 do
    local ia, ib, ic = self.ilist[i + 0], self.ilist[i + 1], self.ilist[i + 2]
    if graph[ia] then graph[ia][ib] = true else graph[ia] = { [ib] = true} end
    if graph[ia] then graph[ia][ic] = true else graph[ia] = { [ic] = true} end
    if graph[ib] then graph[ib][ia] = true else graph[ib] = { [ia] = true} end
    if graph[ib] then graph[ib][ic] = true else graph[ib] = { [ic] = true} end
    if graph[ic] then graph[ic][ia] = true else graph[ic] = { [ia] = true} end
    if graph[ic] then graph[ic][ib] = true else graph[ic] = { [ib] = true} end
  end
  return graph
end


--- Recompute all the triangle normals in a solid, in-place modification!
function m:updateNormals()
  if not self.ilist then
    self.ilist = {}
    for i = 1, #self.vlist do
      self.ilist[i] = i
    end
  end
  if #self.ilist < 3 then return self end
  local normals = {} -- maps vertex index to list of normals of adjacent faces
  for i = 1, #self.ilist, 3 do
    local vi1, vi2, vi3 = self.ilist[i], self.ilist[i + 1], self.ilist[i + 2]
    local v1 = vector(unpack(self.vlist[vi1]))
    local v2 = vector(unpack(self.vlist[vi2]))
    local v3 = vector(unpack(self.vlist[vi3]))
    local fnormal = (v2 - v1):cross(v3 - v1):normalize()
    normals[vi1] = normals[vi1] or {}
    normals[vi2] = normals[vi2] or {}
    normals[vi3] = normals[vi3] or {}
    table.insert(normals[vi1], { fnormal.x, fnormal.y, fnormal.z })
    table.insert(normals[vi2], { fnormal.x, fnormal.y, fnormal.z })
    table.insert(normals[vi3], { fnormal.x, fnormal.y, fnormal.z })
  end
  for i = 1, #self.vlist do
    if normals[i] then
      local vnormal = vector(0, 0, 0)
      local c = 0
      for _, fnormal in ipairs(normals[i]) do
        vnormal = vnormal + vector(fnormal[1], fnormal[2], fnormal[3])
        c = c + 1
      end
      vnormal = (vnormal * (1 / c)):normalize()
      local v = self.vlist[i]
      v[4], v[5], v[6] = vnormal.x, vnormal.y, vnormal.z
      v[7], v[8], v[9], v[10] = v[7] or 1, v[8] or 1, v[9] or 1, v[10] or 1
    end
  end
  self.normals_dirty = false
  return self
end


function m:jiggleNormals(amount)
  local other = self:clone():updateNormals()
  for i, v in ipairs(other.vlist) do
    local normal = vector(v[4], v[5], v[6])
    normal = (normal + vector(
      (lovr.math.random() - 0.5) * amount,
      (lovr.math.random() - 0.5) * amount,
      (lovr.math.random() - 0.5) * amount
    )):normalize()
    v[4], v[5], v[6] = normal.x, normal.y, normal.z
  end
  other.normals_dirty = false
  return other
end


--- Remove the internal buffer representation of solid to force the refresh
function m:invalidate()
  self.mesh = nil
end


function m:calculateBoundingBox()
  local minx = math.huge
  local maxx = -math.huge
  local miny = math.huge
  local maxy = -math.huge
  local minz = math.huge
  local maxz = -math.huge
  for i, v in ipairs(self.vlist) do
    local x, y, z = unpack(v)
    minx = math.min(minx, x)
    maxx = math.max(maxx, x)
    miny = math.min(miny, y)
    maxy = math.max(maxy, y)
    minz = math.min(minz, z)
    maxz = math.max(maxz, z)
  end
  self.mesh:setBoundingBox(minx, maxx, miny, maxy, minz, maxz)
  return minx, maxx, miny, maxy, minz, maxz
end


-- Regenerate the mesh object from vertices and indices
function m:refresh()
  if self.normals_dirty then self:updateNormals() end
  self.mesh = lovr.graphics.newMesh(self.vbuffer_format, self.vlist, 'cpu')
  self.mesh:setIndices(self.ilist)
  self:calculateBoundingBox()
  return self
end


--- Draw the solid mesh in the supplied pass.
function m:draw(pass, ...)
  if #self.ilist < 3 then return end
  if not self.mesh then
    self:refresh()
  end
  pass:draw(self.mesh, ...)
end


--- Draw the wireframe of a solid and each face's normal.
function m:debugDraw(pass, ...)
  pass:push('state')
  pass:setShader()
  local pose = mat4(...)
  -- wireframe model
  pass:setWireframe(true)
  pass:setColor(0x90d59c)
  self:draw(pass, pose)
  -- annotated indices around vertices
  local randomGenerator = lovr.math.newRandomGenerator(0)
  pass:setWireframe(false)
  for i, v in ipairs(self.vlist) do
    local vc = pose * vector(unpack(v))
    local ne = vector(v[4], v[5], v[6])
    local q = quaternion(pose:getOrientation())
    ne = q * ne
    ne = ne * 0.2
    pass:setColor(0xcc7048)
    pass:line(vc, vc + ne)
    pass:setColor(0x68a8ab)
    pass:sphere(vc, 0.02)
    local ap = vc + vector(
      randomGenerator:randomNormal(0.02, 0),
      randomGenerator:randomNormal(0.02, 0),
      randomGenerator:randomNormal(0.02, 0)
    )
    pass:setColor(0xffffb2)
    pass:text(i, ap, 0.08)
  end
  pass:setWireframe(false)
  pass:pop('state')
end


----- Constructors for solid mesh primitives -----

--- Create an empty solid primitive.
function m.new()
  local self = setmetatable({
    vlist = {}, -- vertices
    ilist = {}, -- indices
    sides = {}, -- maps side name to index list (eg. 'top' = {1,2,3,4})
    normals_dirty = true,
    mesh = nil,
  }, m)
  return self
end


--- Create new solid identical to existing one.
function m:clone()
  local other = m.new()
  for i, vertex in ipairs(self.vlist) do
    other.vlist[i] = {unpack(vertex)}
  end
  for i, index in ipairs(self.ilist) do
    other.ilist[i] = index
  end
  for side, ilist in pairs(self.sides) do
    other.sides[side] = {}
    for i, index in ipairs(ilist) do
      other.sides[side][i] = index
    end
  end
  other.vbuffer_format = self.vbuffer_format
  other.ibuffer_format = self.ibuffer_format
  other.normals_dirty = self.normals_dirty
  return other
end


function m.fromCurve(curve, width, n, DTS)
  width = width or 1
  n = n or 32
  DTS = DTS or 10
  local self = m.new()
  local indicesA, indicesB = {}, {}
  local dt = 1 / (DTS * n)
  local step = (1 - 2 * dt) / n
  local normals = {}
  local points = {}
  for i = 0, n  do
    local t = dt + i * step
    local v1 = vector(curve:evaluate(t - dt))
    local v2 = vector(curve:evaluate(t))
    local v3 = vector(curve:evaluate(t + dt))
    table.insert(points, vector(v2))
    v1 = (v2 - v1)            -- v2 - v1
    v3 = (v3 - v2)            -- v3 - v2
    local nrm = v3:cross(v1):normalize()
    table.insert(normals, vector(nrm))
  end
  for i = 1, #normals do
    local offset = normals[i] * width
    local p = points[i]
    local p1 = p + offset
    local p2 = p - offset
    table.insert(self.vlist, {p1.x, p1.y, p1.z})
    table.insert(indicesA, #self.vlist)
    table.insert(self.vlist, {p2.x, p2.y, p2.z})
    table.insert(indicesB, #self.vlist)
  end
  self.ilist = m.sewindices(indicesA, indicesB)
  return self
end


--- Create the solid shape from CSG representation.
function m.fromCSG(csg)
  local self = m.new()
  for _, p in ipairs(csg.polygons) do
    for j=3,#p.vertices do
      local v = p.vertices[1]
      table.insert(self.vlist, {v.pos.x, v.pos.y, v.pos.z, v.normal.x, v.normal.y, v.normal.z})
      v = p.vertices[j-1]
      table.insert(self.vlist, {v.pos.x, v.pos.y, v.pos.z, v.normal.x, v.normal.y, v.normal.z})
      v = p.vertices[j]
      table.insert(self.vlist, {v.pos.x, v.pos.y, v.pos.z, v.normal.x, v.normal.y, v.normal.z})
      table.insert(self.ilist, #self.ilist + 1)
      table.insert(self.ilist, #self.ilist + 1)
      table.insert(self.ilist, #self.ilist + 1)
    end
  end
  return self
end


--- Construct a solid from list of vertices and optional indices.
function m.fromVertices(vertices, indices)
  local self = m.new()
  for i, vertex in ipairs(vertices) do
    if type(vertex) == 'table' then
      self.vlist[i] = {unpack(vertex)}
    elseif type(vertex) == 'userdata' then
      local x = vertex.x or (vertex[1])
      local y = vertex.y or (vertex[2])
      local z = vertex.z or (vertex[3])
      self.vlist[i] = {x, y, z}
    else
      error('unsupported vertex type')
    end
  end
  if indices then
    for i, index in ipairs(indices) do
      self.ilist[i] = index
    end
  else
    local triangle_vertices = math.floor(#vertices / 3) * 3
    for i = 1, triangle_vertices do
      self.ilist[i] = i
    end
  end
  return self
end


--- Construct a solid from LOVR's Model object.
function m.fromModel(model)
  assert(type(model) == 'userdata' and model.getTriangles, 'unsupported input')
  local vlist_flat, ilist = model:getTriangles()
  local vlist = {}
  for i = 1, #vlist_flat, 3 do
    table.insert(vlist, {vlist_flat[i], vlist_flat[i+1], vlist_flat[i+2]})
  end
  return m.fromVertices(vlist, ilist)
end


--- Construct a solid from LOVR's Mesh object.
function m.fromMesh(mesh)
  assert(type(mesh) == 'userdata' and mesh.getVertices, 'unsupported input')
  return m.fromVertices(mesh:getVertices(), mesh:getIndices())
end


--- Construct a solid from LOVR's Mesh object, handling a mesh that is subset of another
function m.fromModelSlice(model, index)
  local mesh = model:getMesh(index)
  local indices  = mesh:getIndices()
  local vertices = mesh:getVertices()
  local combined_vertices = {}
  for meshIndex = 1, model:getMeshCount() do
    local mesh = model:getMesh(meshIndex)
    local start, count, offset = mesh:getDrawRange()
    for i = start, start + count - 1 do
      local v = vertices[indices[i] + offset]
      table.insert(combined_vertices, { unpack(v) })
    end
  end
  return m.fromVertices(combined_vertices)
end


--- Extract convex hull from LOVR's ConvexShape object.
function m.fromConvexShape(shape)
  local vertices, indices = {}, {}
  for i = 1, shape:getPointCount() do
    local x, y, z = shape:getPoint(i)
    table.insert(vertices, {x, y, z})
  end
  for i = 1, shape:getFaceCount() do
    local face_indices = shape:getFace(i)
    for j = 2, #face_indices - 1 do
      table.insert(indices, face_indices[1])
      table.insert(indices, face_indices[j])
      table.insert(indices, face_indices[j + 1])
    end
  end
  return m.fromVertices(vertices, indices)
end


function m:toObjString()
  local content = {}
  -- vertices
  for i, vertex in ipairs(self.vlist) do
    if vertex[7] and vertex[8] and vertex[9] then
      table.insert(content, string.format("v %f %f %f %f %f %f", vertex[1], vertex[2], vertex[3], vertex[7], vertex[8], vertex[9]))
    else
      table.insert(content, string.format("v %f %f %f", vertex[1], vertex[2], vertex[3]))
    end
  end
  -- normals
  for i, vertex in ipairs(self.vlist) do
    if vertex[4] and vertex[5] and vertex[6] then
      table.insert(content, string.format("vn %f %f %f", vertex[4], vertex[5], vertex[6]))
    end
  end
  -- faces
  for i = 1, #self.ilist, 3 do
    local i1, i2, i3 = self.ilist[i], self.ilist[i+1], self.ilist[i+2]
    table.insert(content, string.format("f %d//%d %d//%d %d//%d",
      i1, i1, i2, i2, i3, i3))
  end
  return table.concat(content, '\n')
end


--- Create a convex hull from set of vertices.
function m.convexHull(vertices_in)
  if #vertices_in < 4 then
    return m.new()
  end
  assert(lovr.physics, 'lovr physics module needs to be enabled in conf.lua')
  local vertices = {}
  for i, vertex in ipairs(vertices_in) do
    table.insert(vertices, vertex.x or vertex[1])
    table.insert(vertices, vertex.y or vertex[2])
    table.insert(vertices, vertex.z or vertex[3])
  end
  local shape = lovr.physics.newConvexShape(vertices)
  local hull = m.fromConvexShape(shape)
  return hull, shape
end


local function superellipsoidPoints(segments, sx, sy, sz, e1, e2)
  segments = segments or 12
  sx, sy, sz = sx or 1, sy or 1, sz or 1
  e1, e2 = e1 or 0.5, e2 or 0.5
  local points = {}
  local function sgn(n)
    return (n >= 0) and 1 or -1
  end
  for theta = -math.pi / 2, math.pi / 2, math.pi / segments do
    for gamma = -math.pi, math.pi, math.pi / segments do
      points[#points + 1] = vector(
        sx * math.cos(theta)^e1 * math.abs(math.cos(gamma))^e2 * sgn(math.cos(gamma)),
        sy * math.cos(theta)^e1 * math.abs(math.sin(gamma))^e2 * sgn(math.sin(gamma)),
        sz * math.abs(math.sin(theta))^e1 * sgn(math.sin(theta)))
    end
  end
  return points
end


--- Super ellipsoids are family of shapes that contains cube, sphere, and in-betweens.
function m.superellipsoid(segments, sx, sy, sz, e1, e2)
  return m.convexHull(superellipsoidPoints(segments, sx, sy, sz, e1, e2))
end


--- Single sided 1x1 plane facing down the -Z axis.
function m.quad(subdivisions)
  local size = 1 / math.floor(subdivisions or 1)
  local self = m.new()
  local epsilon = 1e-6
  for y = -0.5, 0.5 - epsilon, size do
    for x = -0.5, 0.5 - epsilon, size do
      table.insert(self.vlist, {x, y, 0})
      table.insert(self.vlist, {x, y + size, 0})
      table.insert(self.vlist, {x + size, y, 0})
      table.insert(self.vlist, {x + size, y + size, 0})
      listappend(self.ilist, {#self.vlist - 3, #self.vlist - 2, #self.vlist - 1})
      listappend(self.ilist, {#self.vlist - 2, #self.vlist - 0, #self.vlist - 1})
    end
  end
  return self
end


--- N-sided equilateral polygon.
function m.ngon(segments)
  segments = segments or 6
  local self = m.new()
  local vic = segments * 2 + 1
  for i = 0, segments - 1 do
    local theta, v1, v2, vi1, vi2
    theta = i * (2 * math.pi) / segments;
    v1 = {0.5 * math.cos(theta),  0.5 * math.sin(theta), 0}
    theta = (i + 1) * (2 * math.pi) / segments
    v2 = {0.5 * math.cos(theta),  0.5 * math.sin(theta), 0}
    table.insert(self.vlist, v1)
    table.insert(self.vlist, v2)
    vi1, vi2 = #self.vlist - 1, #self.vlist
    listappend(self.ilist, {vic, vi2, vi1})
  end
  table.insert(self.vlist, {0,  0, 0})
  assert(vic, #self.vlist)
  return self
end


--- A cube.
function m.cube()
  local self = m.new()
  local s = 0.5
  self.vlist = {
    {-s, -s, -s}, {-s,  s, -s}, { s, -s, -s}, { s,  s, -s},
    { s,  s, -s}, { s,  s,  s}, { s, -s, -s}, { s, -s,  s},
    { s, -s,  s}, { s,  s,  s}, {-s, -s,  s}, {-s,  s,  s},
    {-s,  s,  s}, {-s,  s, -s}, {-s, -s,  s}, {-s, -s, -s},
    {-s, -s, -s}, { s, -s, -s}, {-s, -s,  s}, { s, -s,  s},
    {-s,  s, -s}, {-s,  s,  s}, { s,  s, -s}, { s,  s,  s}}
  self.ilist = {
     1,  2,  3,  3,  2,  4,
     5,  6,  7,  7,  6,  8,
     9, 10, 11, 11, 10, 12,
    13, 14, 15, 15, 14, 16,
    17, 18, 19, 19, 18, 20,
    21, 22, 23, 23, 22, 24}
  self.sides = {
    right =  {3, 4,  5,  6,  7,  8,  9, 10, 18, 20, 23, 24},
    bottom = {1, 3,  7,  8,  9, 11, 15, 16, 17, 18, 19, 20},
    back =   {6, 8,  9, 10, 11, 12, 13, 15, 19, 20, 22, 24},
    top =    {2, 4,  5,  6, 10, 12, 13, 14, 21, 22, 23, 24},
    front =  {1, 2,  3,  4,  5,  7, 14, 16, 17, 18, 21, 23},
    left =   {1, 2, 11, 12, 13, 14, 15, 16, 17, 19, 21, 22}}
  return self
end


--- A truncated cube (rhombicuboctahedron) with variable slant cutoff.
function m.tcube(slant)
  local self = m.new()
  slant = slant or 0.8
  slant = math.min(math.max(slant, 0), 1)
  local s, l = slant * 0.5, 0.5
  self.vlist = {
    {-s, -l,  s}, {-s, -s,  l}, {-l, -s,  s}, {-s,  s,  l},
    {-s,  l,  s}, {-l,  s,  s}, {-s, -l, -s}, {-l, -s, -s},
    {-s, -s, -l}, {-s,  l, -s}, {-s,  s, -l}, {-l,  s, -s},
    { s, -l,  s}, { l, -s,  s}, { s, -s,  l}, { s,  l,  s},
    { s,  s,  l}, { l,  s,  s}, { s, -l, -s}, { s, -s, -l},
    { l, -s, -s}, { s,  l, -s}, { l,  s, -s}, { s,  s, -l},
  }
  self.ilist = {
    15,  4,  2,   21, 18, 14,   22,  5, 16,    3, 12,  8,
     9, 24, 20,    1,  2,  3,    4,  5,  6,    7,  8,  9,
    10, 11, 12,   13, 14, 15,   16, 17, 18,   19, 20, 21,
    22, 23, 24,    7,  3,  8,    2,  6,  3,    5, 12,  6,
    11,  8, 12,   19,  9, 20,   10, 24, 11,   23, 20, 24,
    13, 21, 14,   22, 18, 23,   17, 14, 18,    1, 15,  2,
    16,  4, 17,    7, 13,  1,   15, 17,  4,   21, 23, 18,
    22, 10,  5,    3,  6, 12,    9, 11, 24,    7,  1,  3,
     2,  4,  6,    5, 10, 12,   11,  9,  8,   19,  7,  9,
    10, 22, 24,   23, 21, 20,   13, 19, 21,   22, 16, 18,
    17, 15, 14,    1, 13, 15,   16,  5,  4,    7, 19, 13,
  }
  self.sides = {
    right =  {13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24},
    bottom = { 1,  2,  3,  7,  8,  9, 13, 14, 15, 19, 20, 21},
    back =   { 1,  2,  3,  4,  5,  6, 13, 14, 15, 16, 17, 18},
    top =    { 4,  5,  6, 10, 11, 12, 16, 17, 18, 22, 23, 24},
    front =  { 7,  8,  9, 10, 11, 12, 19, 20, 21, 22, 23, 24},
    left =   { 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12},
  }
  return self
end


--- Bipyramid with variable number of sides (a diamond shape).
function m.bipyramid(segments)
  local self = m.new()
  segments = segments or 4
  self.sides = {top={}, bottom={}, ring={}}
  for i = 0, segments - 1 do
    -- top half
    table.insert(self.vlist,  {0, 0.5, 0})
    table.insert(self.sides.top, #self.vlist)
    local theta = i * (2 * math.pi) / segments
    local x = 0.5 * math.cos(theta)
    local z = 0.5 * math.sin(theta)
    table.insert(self.vlist, {x, 0, z})
    table.insert(self.sides.ring, #self.vlist)
    theta = (i + 1) * (2 * math.pi) / segments
    x = 0.5 * math.cos(theta)
    z = 0.5 * math.sin(theta)
    table.insert(self.vlist, {x, 0, z})
    table.insert(self.sides.ring, #self.vlist)
    listappend(self.ilist, {#self.vlist, #self.vlist - 1, #self.vlist - 2})
    -- bottom half
    table.insert(self.vlist,  {0, -0.5, 0})
    table.insert(self.sides.bottom, #self.vlist)
    theta = i * (2 * math.pi) / segments
    x = 0.5 * math.cos(theta)
    z = 0.5 * math.sin(theta)
    table.insert(self.vlist, {x, 0, z})
    table.insert(self.sides.ring, #self.vlist)
    theta = (i + 1) * (2 * math.pi) / segments
    x = 0.5 * math.cos(theta)
    z = 0.5 * math.sin(theta)
    table.insert(self.vlist, {x, 0, z})
    table.insert(self.sides.ring, #self.vlist)
    listappend(self.ilist, {#self.vlist, #self.vlist - 2, #self.vlist - 1})
  end
  return self
end


--- A pyramid with variable number of sides.
function m.pyramid(segments)
  local self = m.bipyramid(segments)
  self = self:transform(mat4(0, -0.5, 0), self.sides.ring)
  listappend(self.sides.bottom, self.sides.ring)
  return self
end


--- A prism with variable number of sides.
function m.cylinder(segments)
  local self = m.new()
  segments = segments or 6
  self.sides = {top={}, bottom={}, ring={}}
  local vTop = segments * 8 + 1
  local vBottom = segments * 8 + 2
  for i = 0, segments - 1 do
    -- ring
    local theta, v1, v2, v3, v4, vi1, vi2, vi3, vi4
    theta = i * (2 * math.pi) / segments;
    v1 = {0.5 * math.cos(theta), -0.5, 0.5 * math.sin(theta)}
    v2 = {0.5 * math.cos(theta),  0.5, 0.5 * math.sin(theta)}
    theta = (i + 1) * (2 * math.pi) / segments;
    v3 = {0.5 * math.cos(theta), -0.5, 0.5 * math.sin(theta)}
    v4 = {0.5 * math.cos(theta),  0.5, 0.5 * math.sin(theta)}
    table.insert(self.vlist, v1)
    table.insert(self.sides.bottom, #self.vlist)
    table.insert(self.vlist, v2)
    table.insert(self.sides.top, #self.vlist)
    table.insert(self.vlist, v3)
    table.insert(self.sides.bottom, #self.vlist)
    table.insert(self.vlist, v4)
    table.insert(self.sides.top, #self.vlist)
    vi1, vi2, vi3, vi4 = #self.vlist-3, #self.vlist-2, #self.vlist-1, #self.vlist
    listappend(self.ilist, {vi1, vi2, vi4, vi1, vi4, vi3})
    -- top and bottom self.sides
    theta = i * (2 * math.pi) / segments;
    v1 = {0.5 * math.cos(theta), -0.5, 0.5 * math.sin(theta)}
    v2 = {0.5 * math.cos(theta),  0.5, 0.5 * math.sin(theta)}
    theta = (i + 1) * (2 * math.pi) / segments;
    v3 = {0.5 * math.cos(theta), -0.5, 0.5 * math.sin(theta)}
    v4 = {0.5 * math.cos(theta),  0.5, 0.5 * math.sin(theta)}
    table.insert(self.vlist, v1)
    table.insert(self.sides.bottom, #self.vlist)
    table.insert(self.vlist, v2)
    table.insert(self.sides.top, #self.vlist)
    table.insert(self.vlist, v3)
    table.insert(self.sides.bottom, #self.vlist)
    table.insert(self.vlist, v4)
    table.insert(self.sides.top, #self.vlist)
    vi1, vi2, vi3, vi4 = #self.vlist-3, #self.vlist-2, #self.vlist-1, #self.vlist
    listappend(self.ilist, {vTop, vi4, vi2, vBottom, vi1, vi3})
  end
  table.insert(self.vlist, {0,  0.5, 0})
  table.insert(self.sides.top, #self.vlist)
  assert(vTop, #self.vlist)
  table.insert(self.vlist, {0, -0.5, 0})
  table.insert(self.sides.bottom, #self.vlist)
  assert(vBottom, #self.vlist)
  return self
end


--- Icosphere with customizable subdivision steps (each is x4 geometry)
function m.sphere(subdivisions)
  local self = m.new()
  subdivisions = subdivisions or 2
  local phi = (1 + math.sqrt(5)) / 2
  self.vlist = {
    { -1,  phi, 0 }, {  1,  phi, 0 }, { -1, -phi, 0 }, {  1, -phi, 0 },
    { 0, -1,  phi }, { 0,  1,  phi }, { 0, -1, -phi }, { 0,  1, -phi },
    {  phi, 0, -1 }, {  phi, 0,  1 }, { -phi, 0, -1 }, { -phi, 0,  1 }
  }
  self.ilist = {
    1, 12, 6,  1, 6, 2,  1, 2, 8,  1, 8, 11,  1, 11, 12,
    2, 6, 10,  6, 12, 5,  12, 11, 3,  11, 8, 7,  8, 2, 9,
    4, 10, 5,  4, 5, 3,  4, 3, 7,  4, 7, 9,  4, 9, 10,
    5, 10, 6,  3, 5, 12,  7, 3, 11,  9, 7, 8,  10, 9, 2
  }
  local splits = {}
  local function split(i, j)
    local key = i < j and (i .. ',' .. j) or (j .. ',' .. i)
    if not splits[key] then
      local x = (self.vlist[i][1] + self.vlist[j][1]) / 2
      local y = (self.vlist[i][2] + self.vlist[j][2]) / 2
      local z = (self.vlist[i][3] + self.vlist[j][3]) / 2
      table.insert(self.vlist, { x, y, z })
      splits[key] = #self.vlist
    end
    return splits[key]
  end
  for _ = 1, subdivisions do
    for i = #self.ilist, 1, -3 do
      local v1, v2, v3 = self.ilist[i - 2], self.ilist[i - 1], self.ilist[i - 0]
      local a = split(v1, v2)
      local b = split(v2, v3)
      local c = split(v3, v1)

      table.insert(self.ilist, v1); table.insert(self.ilist, a); table.insert(self.ilist, c)
      table.insert(self.ilist, v2); table.insert(self.ilist, b); table.insert(self.ilist, a)
      table.insert(self.ilist, v3); table.insert(self.ilist, c); table.insert(self.ilist, b)
      table.insert(self.ilist, a);  table.insert(self.ilist, b); table.insert(self.ilist, c)

      table.remove(self.ilist, i - 0)
      table.remove(self.ilist, i - 1)
      table.remove(self.ilist, i - 2)
    end
  end
  for _, v in ipairs(self.vlist) do
    local x, y, z = unpack(v)
    local length = math.sqrt(x * x + y * y + z * z) * 2
    v[1], v[2], v[3] = x / length, y / length, z / length
  end
  return self
end


--[[ Octasphere utilities (migrated to Luau vectors) ]]

--- Create list of indices that sews together two lists of indices.
function m.sewindices(edgeA, edgeB, offsetA, offsetB)
  assert(#edgeA == #edgeB)
  offsetA, offsetB = offsetA or 0, offsetB or 0
  local indices = {}
  for i = 1, #edgeA - 1 do
    local cA, cB = edgeA[i], edgeB[i]
    local nA, nB = edgeA[i + 1], edgeB[i + 1]
    table.insert(indices, cA + offsetA)
    table.insert(indices, nB + offsetB)
    table.insert(indices, nA + offsetA)
    table.insert(indices, cA + offsetA)
    table.insert(indices, cB + offsetB)
    table.insert(indices, nB + offsetB)
  end
  return indices
end


-- Construct a list of vertices inside a geodesic.
local function compute_geodesic(point_a, point_b, num_segments)
  local angle_between_endpoints = math.acos( point_a:dot(point_b) )
  local rotation_axis = vector(point_a):cross(point_b)
  local first = vector(point_a)
  local point_list = { { first.x, first.y, first.z } }
  if num_segments == 0 then
    return point_list
  end
  local dtheta = angle_between_endpoints / num_segments
  for point_index = 1, num_segments - 1 do
    local theta = point_index * dtheta
    local q = quaternion(theta, rotation_axis.x, rotation_axis.y, rotation_axis.z)
    local p = q * point_a
    table.insert(point_list, { p.x, p.y, p.z })
  end
  local last = vector(point_b)
  table.insert(point_list, { last.x, last.y, last.z })
  return point_list
end


--- Subdivide an octant into vertical slices and construct geodesic of each.
local function tessellate_octasphere_patch(subdivisions)
  local n = 2^subdivisions + 1
  local num_vertices = n * (n + 1) / 2
  local vertices = {}
  for i = 0, n - 1 do
    local theta = math.pi * 0.5 * i / (n - 1)
    local point_a = vector(0,               math.sin(theta), math.cos(theta))
    local point_b = vector(math.cos(theta), math.sin(theta), 0)
    local num_segments = n - 1 - i
    local geodesic_vertices = compute_geodesic(point_a, point_b, num_segments)
    for _, vertex in ipairs(geodesic_vertices) do
      table.insert(vertices, vertex)
    end
  end
  assert(#vertices == num_vertices)
  -- construct indices for single octasphere patch
  local indices = {}
  local f, j0 = 1, 1
  for col_index = 0, n-2 do
    local col_height = n - 1 - col_index
    local j1 = j0 + 1
    local j2 = j0 + col_height + 1
    local j3 = j0 + col_height + 2
    for row = 0, col_height - 2 do
      table.insert(indices, j0 + row)
      table.insert(indices, j1 + row)
      table.insert(indices, j2 + row)
      table.insert(indices, j2 + row)
      table.insert(indices, j1 + row)
      table.insert(indices, j3 + row)
      f = f + 2
    end
    local row = col_height - 1
    table.insert(indices, j0 + row)
    table.insert(indices, j1 + row)
    table.insert(indices, j2 + row)
    f = f + 1
    j0 = j2
  end
  -- identify indices of vertices on edges
  local edges = {x = {}, y = {}, z = {}}
  local step = n
  local xi = 1
  local zi = n
  for i = 1, n do
    table.insert(edges.y, i)
    table.insert(edges.x, xi)
    table.insert(edges.z, zi)
    xi = xi + step
    step = step - 1
    zi = zi + step
  end
  return vertices, indices, edges
end


local function sign(n)
  return (n < 0 and -1) or 1
end


local function reshape_octasphere(solid, rx, ry, rz, ex, ey, ez, slant)
  slant = math.max(-1, math.min(1, slant or 0))
  return solid:map(
    function(x,y,z)
      x = sign(x) * ex / 2 + (x - sign(x)) / 2 * rx
      y = sign(y) * ey / 2 + (y - sign(y)) / 2 * ry
      z = sign(z) * ez / 2 + (z - sign(z)) / 2 * rz
      x = x * (1 + (z / (ez / 2 + rz)) * slant)
      y = y * (1 + (z / (ez / 2 + rz)) * slant)
      return x, y, z
    end)
end


function m.octasphere(subdivisions)
  local mergedvertices = {}
  local mergedindices  = {}
  local patchvertices, patchindices, patchedges = tessellate_octasphere_patch(subdivisions)
  local patchindicesflipped = {}
  for i = 1, #patchindices, 3 do
    patchindicesflipped[i]     = patchindices[i]
    patchindicesflipped[i + 1] = patchindices[i + 2]
    patchindicesflipped[i + 2] = patchindices[i + 1]
  end
  local reflections = {
                  [1] = {  1,  1,  1 },
                  [2] = {  1,  1, -1 },
                  [3] = {  1, -1,  1 },
                  [4] = {  1, -1, -1 },
                  [5] = { -1,  1,  1 },
                  [6] = { -1,  1, -1 },
                  [7] = { -1, -1,  1 },
                  [8] = { -1, -1, -1 }}
  local patchcount = #patchvertices
  for ri, refl in ipairs(reflections) do
    local rx, ry, rz = refl[1], refl[2], refl[3]
    for _,v in ipairs(patchvertices) do
      local rv = vector(v[1], v[2], v[3])
      -- spread apart 8 domes so that no two points are on same coordinates
      rv = rv + vector(1, 1, 1)
      local x, y, z = rv.x * rx, rv.y * ry, rv.z * rz
      local nv = vector(v[1] * rx, v[2] * ry, v[3] * rz)
      table.insert(mergedvertices, { x, y, z, nv.x, nv.y, nv.z })
    end
    local offset = (ri - 1) * patchcount
    local indices = (rx * ry * rz > 0) and patchindices or patchindicesflipped
    for _,i in ipairs(indices) do
      table.insert(mergedindices, i + offset)
    end
  end
  local rotationstiches = {
    {},
    {{ 1, 'z', true }},
    {{ 1, 'y', true }},
    {{ 2, 'y' }, { 3, 'z' }},
    {{ 1, 'x' }},
    {{ 2, 'x', true }, { 5, 'z' }},
    {{ 3, 'x', true }, { 5, 'y' }},
    {{ 4, 'x' }, { 6, 'y', true }, { 7, 'z', true }}}
  for ri, stitchdefs in ipairs(rotationstiches) do
      for _, stitchdef in ipairs(stitchdefs) do
        local ti, axis, flip = unpack(stitchdef)
        local offsetA = (ri - 1) * patchcount
        local offsetB = (ti - 1) * patchcount
        if flip then
          offsetA, offsetB = offsetB, offsetA
        end
        local stitch = m.sewindices(patchedges[axis], patchedges[axis], offsetA, offsetB)
        for _, index in ipairs(stitch) do
          table.insert(mergedindices, index)
        end
      end
  end
  local faces = {  {{0, 2}, {4, 6}, patchedges.x[1]},
                   {{1, 3}, {0, 2}, patchedges.z[1]},
                   {{4, 6}, {5, 7}, patchedges.z[1]},
                   {{5, 7}, {1, 3}, patchedges.x[1]},
                   {{4, 5}, {0, 1}, patchedges.x[#patchedges.x]},
                   {{6, 2}, {7, 3}, patchedges.x[#patchedges.x]}}
  for _, face in ipairs(faces) do
    local edgeA = {face[1][1] * patchcount + face[3], face[1][2] * patchcount + face[3]}
    local edgeB = {face[2][1] * patchcount + face[3], face[2][2] * patchcount + face[3]}
    local stitch = m.sewindices(edgeA, edgeB)
    for _, index in ipairs(stitch) do
      table.insert(mergedindices, index)
    end
  end
  local solid = m.fromVertices(mergedvertices, mergedindices)
  solid.subdivisions = subdivisions
  solid.reshape = reshape_octasphere
  return solid
end


return m
