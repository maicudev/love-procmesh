local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_union', function(self, menori)
  local mat4 = menori.ml.mat4
  local cube = solids.cube():transform(
    mat4():scale(1.65, 1.65, 1.65))
  local sphere = solids.sphere(2):transform(
    mat4():translate(0.85, 0.0, 0):scale(0.9, 0.9, 0.9))

  local result = solids.fromCSG(csg.fromSolid(cube):union(csg.fromSolid(sphere)))
  assert(#result.ilist > 0 and result:volume() > cube:volume(),
    'CSG union did not add volume')
  self:add_solid(result, {0.95, 0.56, 0.2, 1})
  self:set_edges_enabled(true)
end)
