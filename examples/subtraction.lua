local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_subtraction', function(self, menori)
  local mat4 = menori.ml.mat4
  local cube = solids.cube():transform(
    mat4():scale(1.65, 1.65, 1.65))
  local cube2 = solids.cube():transform(
    mat4():translate(0.5, 0.0, 0.0):scale(1.0, 1.0, 1.0))
  local sphere = solids.sphere(2):transform(
    mat4():translate(-0.85, 0, 0):scale(0.9, 0.9, 0.9))

  local csgCube = csg.fromSolid(cube)
  local csgCube2 = csg.fromSolid(cube2)
  local csgSphere = csg.fromSolid(sphere)

  local csgRes = csgCube:subtract(csgCube2)
  csgRes = csgRes:subtract(csgSphere)

  local result = solids.fromCSG(csgRes)
  -- assert(#result.ilist > 0 and result:volume() < cube:volume(),
  --   'CSG subtraction did not remove volume')
  self:add_solid(result, {0.25, 0.72, 0.92, 1})
  self:set_edges_enabled(true)
end)
