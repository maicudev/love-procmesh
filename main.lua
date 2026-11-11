package.path = package.path .. ';menori/?/init.lua;menori/?.lua'

local lreadfile = love.filesystem.read
love.filesystem.read = function (path, ...)
  if path:sub(1, 7) == 'menori/' then
    path = 'menori/' .. path
  end
  return lreadfile(path, ...)
end

local menori = require 'menori'

local examples = {
  { title = 'Subtraction', module = 'examples.subtraction' },
  { title = 'Union', module = 'examples.union' },
  { title = 'Intersection', module = 'examples.intersection' }
}
local current_example = 1
local current_scene
local loaded_scenes = {}
local canvas

local function load_example(index)
  current_example = index
  if not loaded_scenes[index] then
    local scene_class = require(examples[index].module)
    loaded_scenes[index] = scene_class()
  end
  current_scene = loaded_scenes[index]
end

function love.load()
  for index = 1, #examples do
    load_example(index)
  end
  load_example(current_example)
  local width, height = love.graphics.getDimensions()
  canvas = love.graphics.newCanvas(width, height)
end

function love.update(dt)
  current_scene:update(dt)
end

function love.draw()
  love.graphics.setCanvas({ canvas, depth = true })
  current_scene:render()
  love.graphics.setCanvas()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas)

  local width, height = love.graphics.getDimensions()
  love.graphics.print('Example: ' .. examples[current_example].title, 12, 12)
  love.graphics.print('LMB + drag: orbit    Wheel: zoom    F: edges    Q / E: example    Esc: quit', 12, height - 24)
end

function love.keypressed(key)
  if key == 'escape' then
    love.event.quit()
  elseif key == 'f' then
    current_scene:set_edges_enabled(not current_scene.edges_enabled)
  elseif key == 'q' or key == 'e' then
    local direction = key == 'e' and 1 or -1
    load_example((current_example - 1 + direction) % #examples + 1)
  end
end

function love.mousemoved(...)
  current_scene:mousemoved(...)
end

function love.wheelmoved(...)
  current_scene:wheelmoved(...)
end

function love.resize(width, height)
  canvas = love.graphics.newCanvas(width, height)
end
