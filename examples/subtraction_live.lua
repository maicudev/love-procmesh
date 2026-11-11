local solids = require 'solids'
local csg = require 'csg'
local common = require 'examples.common'
local menori = require 'menori'

local cutter_scale = {x = 0.8, y = 1.2, z = 0.8}
local cutter_y = 0.6

local scene = common.scene('procmesh_live_subtraction', function(self, menori)
  local mat4 = menori.ml.mat4
  self.target_csg = csg.fromSolid(solids.cube():transform(
    mat4():translate(0, 0.5, 0):scale(2.4, 1, 1.8)))
  self.cutter_position = menori.ml.vec3(0.55, cutter_y, 0)

  local initial_cutter = solids.cube():transform(
    mat4():translate(self.cutter_position):scale(cutter_scale))
  local initial_result = solids.fromCSG(
    self.target_csg:subtract(csg.fromSolid(initial_cutter)))
  self.result_surface, self.result_edges = self:add_solid(
    initial_result, {0.25, 0.72, 0.92, 1})

  self.cutter_surface, self.cutter_edges = self:add_solid(
    solids.cube(), {1, 0.45, 0.2, 1})
  for _, node in ipairs({self.cutter_surface, self.cutter_edges}) do
    node:set_position(self.cutter_position)
    node:set_scale(cutter_scale)
  end
  self.cutter_surface:recursive_update_transform(true)
  self.cutter_surface.bvh = menori.ml.bvh(self.cutter_surface)

  self:set_edges_enabled(false)
  self.result_edges.render_flag = false
  self.cutter_surface.render_flag = false
  self.cutter_edges.render_flag = true
  self.cutter_edges.material:set('baseColor', {1, 0.45, 0.2, 1})
  self.hint = 'Drag the orange cutter with LMB; subtraction updates live'
end)

function scene:update_subtraction()
  local mat4 = menori.ml.mat4
  local cutter = solids.cube():transform(
    mat4():translate(self.cutter_position):scale(cutter_scale))
  local result = solids.fromCSG(
    self.target_csg:subtract(csg.fromSolid(cutter)))
  local mesh = result:toMenoriMesh(menori)
  self.result_surface.mesh = mesh
  self.result_edges.mesh = mesh
end

function scene:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  local width, height = love.graphics.getDimensions()
  local ray = self.camera:screen_point_to_ray(x, y, {0, 0, width, height})
  if #self.cutter_surface.bvh:intersect_ray(ray) == 0 then
    return
  end

  local hit = menori.ml.intersect.ray_plane(
    ray, menori.ml.vec3(0, 0, 0), menori.ml.vec3.unit_y)
  if hit then
    self.drag_offset_x = self.cutter_position.x - hit.point[1]
    self.drag_offset_z = self.cutter_position.z - hit.point[3]
    self.dragging_cutter = true
  end
end

function scene:mousereleased(_, _, button)
  if button == 1 then
    self.dragging_cutter = false
  end
end


local scene_mousemoved = scene.mousemoved

function scene:mousemoved(x, y, dx, dy)
  if not self.dragging_cutter then
    scene_mousemoved(self, x, y, dx, dy)
    return
  end

  local width, height = love.graphics.getDimensions()
  local ray = self.camera:screen_point_to_ray(x, y, {0, 0, width, height})
  local hit = menori.ml.intersect.ray_plane(
    ray, menori.ml.vec3(0, 0, 0), menori.ml.vec3.unit_y)
  if not hit then
    return
  end

  self.cutter_position.x = hit.point[1] + self.drag_offset_x
  self.cutter_position.z = hit.point[3] + self.drag_offset_z
  self.cutter_surface:set_position(self.cutter_position)
  self.cutter_edges:set_position(self.cutter_position)
  self.cutter_surface:recursive_update_transform(true)
  self.cutter_surface.bvh = menori.ml.bvh(self.cutter_surface)
  self:update_subtraction()
end

return scene
