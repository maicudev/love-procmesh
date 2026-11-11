local menori = require 'menori'

local common = {}

local lighting_frag = menori.utils.shader_preprocess(love.filesystem.read('examples/basic_lighting_frag.glsl'))
local DirectionalLight = menori.UniformList:extend('DirectionalLight')
function DirectionalLight:init(x, y, z, r, g, b)
	DirectionalLight.super.init(self)

	self:set('direction', {x, y, z})
	self:set('ambient', {r * 0.18, g * 0.18, b * 0.18})
	self:set('diffuse', {r, g, b})
	self:set('specular', {r * 0.2, g * 0.2, b * 0.2})
end

function common.scene(name, build)
  local scene = menori.Scene:extend(name)

  function scene:init()
    scene.super.init(self)

    local _, _, width, height = menori.app:get_viewport()
    self.camera = menori.PerspectiveCamera(50, width / height, 0.1, 100)
    self.environment = menori.Environment(self.camera)
    self.environment:add_light('directional_lights', DirectionalLight(-0.5, -1, -0.6, 1, 1, 1))
    self.root_node = menori.Node()
    self.angle = 25
    self.elevation = 18
    self.distance = 4.5
    self.edge_nodes = {}
    build(self, menori)
    self:update_camera()
  end

  function scene:add_solid(solid, color)
    local surface_material = menori.Material()
    surface_material:set('baseColor', color)
    surface_material:set_shader_code(nil, lighting_frag)

    local edge_material = menori.Material()
    edge_material:set('baseColor', {0.035, 0.045, 0.06, 1})
    edge_material.wireframe = true
    edge_material.mesh_cull_mode = 'none'
    edge_material.depth_func = 'lequal'

    local mesh = solid:toMenoriMesh(menori)
    local surface = menori.ModelNode(mesh, surface_material)
    local edges = menori.ModelNode(mesh, edge_material)
    surface.layer = 0
    edges.layer = 1
    self.root_node:attach(surface)
    self.root_node:attach(edges)
    table.insert(self.edge_nodes, edges)
  end

  function scene:set_edges_enabled(enabled)
    self.edges_enabled = enabled
    for _, node in ipairs(self.edge_nodes) do
      node.render_flag = enabled
    end
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
      self.elevation = math.max(-80, math.min(80, self.elevation - dy * 0.35))
      self:update_camera()
    end
  end

  function scene:wheelmoved(_, y)
    self.distance = math.max(0.2, math.min(12, self.distance * math.exp(-y * 0.12)))
    self:update_camera()
  end

  function scene:update()
    self:update_nodes(self.root_node, self.environment)
  end

  function scene:render()
    love.graphics.clear(0.08, 0.1, 0.15, 1)
    self:render_nodes(self.root_node, self.environment, {
      node_sort_comp = menori.Scene.layer_comp
    })
  end

  return scene
end

return common
