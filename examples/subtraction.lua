local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_subtraction', function(self, menori)
  local mat4 = menori.ml.mat4
  local base = solids.cube():transform(mat4():scale(1.65, 1.65, 1.65))
  local cutter = solids.sphere(2):transform(
    mat4():translate(0.85, 0, 0):scale(0.9, 0.9, 0.9))

  local result = solids.fromCSG(csg.fromSolid(base):subtract(csg.fromSolid(cutter)))
  assert(#result.ilist > 0 and result:volume() < base:volume(),
    'CSG subtraction did not remove volume')
  local material = menori.Material()
  material:set('baseColor', {0.25, 0.72, 0.92, 1})
  self.root_node:attach(result:toMenoriNode(menori, material))
end)
