local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_intersection', function(self, menori)
  local mat4 = menori.ml.mat4
  local cube = solids.cube():transform(
    mat4():scale(1.65, 1.65, 1.65))
  local sphere = solids.sphere(1):transform(
    mat4():translate(0.85, 0, 0):scale(0.9, 0.9, 0.9))

  local result = solids.fromCSG(csg.fromSolid(cube):intersect(csg.fromSolid(sphere)))
  assert(#result.ilist > 0 and result:volume() > 0
      and result:volume() < math.min(cube:volume(), sphere:volume()),
    'CSG intersection did not produce the overlapping volume')
  self:add_solid(result, {0.48, 0.82, 0.42, 1})
  self:set_edges_enabled(true)
end)
