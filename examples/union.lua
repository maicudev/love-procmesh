local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'

return common.scene('procmesh_union', function(self, menori)
  local mat4 = menori.ml.mat4
  local cube = solids.cube():transform(
    mat4():translate(-0.35, 0, 0):scale(1.2, 1.2, 1.2))
  local sphere = solids.sphere(2):transform(
    mat4():translate(0.85, 0, 0):scale(0.8, 0.8, 0.8))

  local result = solids.fromCSG(csg.fromSolid(cube):union(csg.fromSolid(sphere)))
  assert(#result.ilist > 0 and result:volume() > cube:volume(),
    'CSG union did not add volume')
  local material = menori.Material()
  material:set('baseColor', {0.95, 0.56, 0.2, 1})
  self.root_node:attach(result:toMenoriNode(menori, material))
end)
