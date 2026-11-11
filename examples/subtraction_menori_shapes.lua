local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_subtraction_menori_shapes', function(self, menori)
  local mat4 = menori.ml.mat4
  local box = solids.fromMenoriShape(menori.Box(1, 1, 1))
  local capsule = solids.fromMenoriShape(menori.Capsule(0.3, 1, 8, 3, 1))

  local result = solids.fromCSG(csg.fromSolid(box):subtract(csg.fromSolid(capsule)))
  assert(#result.ilist > 0 and result:volume() < box:volume(),
    'CSG subtraction did not remove volume')
  self:add_solid(result, {0.25, 0.72, 0.92, 1})
  self:set_edges_enabled(false)
end)
