local menori = require 'menori'

local common = {}

function common.scene(name, build)
  local scene = menori.Scene:extend(name)

  function scene:init()
    scene.super.init(self)

    local _, _, width, height = menori.app:get_viewport()
    self.camera = menori.PerspectiveCamera(50, width / height, 0.1, 100)
    self.environment = menori.Environment(self.camera)
    self.root_node = menori.Node()
    self.angle = 25
    self.elevation = 18
    self.distance = 3.2
    build(self, menori)
    self:update_camera()
  end

  function scene:update_camera()
    local ml = menori.ml
    local center = ml.vec3(0, 0, 0)
    local offset = ml.quat.from_euler_angles(0, math.rad(self.angle), math.rad(self.elevation))
      * ml.vec3.unit_z * self.distance
    self.camera.center = center
    self.camera.eye = center + offset
    self.camera:update_view_matrix()
  end

  function scene:mousemoved(_, _, dx, dy)
    if love.mouse.isDown(1) then
      self.angle = self.angle - dx * 0.35
      self.elevation = math.max(-80, math.min(80, self.elevation + dy * 0.35))
      self:update_camera()
    end
  end

  function scene:wheelmoved(_, y)
    self.distance = math.max(1.2, math.min(12, self.distance * math.exp(-y * 0.12)))
    self:update_camera()
  end

  function scene:update()
    self:update_nodes(self.root_node, self.environment)
  end

  function scene:render()
    love.graphics.clear(0.08, 0.1, 0.15, 1)
    self:render_nodes(self.root_node, self.environment, {
      node_sort_comp = menori.Scene.alpha_mode_comp
    })
  end

  return scene
end

return common
