# solids

![showcase of solids](/home/josip/vrdev/frameworks/procmesh/media/solids.png "Showcase of solids")

The `solids.lua` module can be used to create some geometric primitives from scratch, and to preform operations on vertices and indices.

```Lua
solids = require('solids')
cube_solid = solids.cube()

function lovr.draw(pass)
  cube_solid:draw(pass, 0, 2, -2)
  local time = lovr.timer.getTime()
  cube_solid:draw(pass, mat4(0, 1, -2,   time, 0, 1, 0))
end
```

The advantage over LÖVR built-in primitives is ability to manipulate the mesh before rendering. The disadvantage is that UV maps are not computed, so textures and surface shader effects won't work with them.

The `solid` primitive stores the geometry information in a table:

```Lua
{
  vlist = { {0,0,0,_}, {1,2,3,_}, _} -- list of vertices storing data (positions, normals, colors...)
  ilist = {1, 2, 3, _},              -- flat list of indices; triplets that from the triangles
  sides = {top = {1, 2, 3, _}, _}    -- shape sides mapped to the list of indices
  vbuffer = Buffer(),                -- vertex buffer object for rendering, regenerated as needed
  ibuffer = Buffer(),                -- index buffer object for rendering, regenerated as needed
} -- with metatable accessors to manipulating functions
```

Vertices are stored in nested table `vlist`. Single vertex is a table with 3 or more values. First three values are XYZ coordinates; they can be followed by 3 numerical components of a normal vector, and even more vertex data after that.

Indices in flat `ilist` table are used to construct all the triangles of geometry. Each number is a 1-based index into the vertex table.

Such primitive can be constructed by calling any of the geometry constructors. Currently included primitive solids are:

* `quad(subdivisions)` a 2D rectangle, with optional subdivision into grid
* `ngon(segments)` an N-sided equilateral polygon
* `cube()` a simple cube with 6 sides
* `tcube(slant)` a truncated cube (rhombicuboctahedron) with variable slant cutoff
* `bipyramid(segments)` a bipyramid with variable number of sides (a diamond shape)
* `pyramid(segments)`  a pyramid with variable number of sides
* `cylinder(segments)` a prism with variable number of sides
* `sphere(subdivisions)` an icosphere with customizable subdivision steps
* `octasphere(subdivisions)` a versatile sphere-cube geometry
* `superellipsoid(segments, sx, sy, sz, e1, e2)` a family of shapes that contains cube, sphere, and in-betweens

While creating the geometry, most of the above functions group the vertices into sides. Indices for different sides are stored under the `sides` map inside the solid object. For example, a cylinder has a bottom and top side. Such a table can be used to selectively manipulate only some parts of the mesh.

In general the vertices of adjacent faces are not shared. This allows colocated vertices to have different normals, for example the cube has hard edges when rendered with the appropriate shader. Even for the cylinder, the curved surface subdivided into segments has a separate non-smoothed normal for each segment. This is in line with low-polygon aesthetics which is the intended use of this library.


### Octasphere

While the rest of primitives are mostly straight-forward, the [octasphere](https://prideout.net/blog/octasphere/) deserves a detailed description. It is a geometric primitive constructed by slicing a sphere into 8 separate octants, and then stitching them together with quads. By extruding and manipulating quad lengths it is possible to coerce the octasphere into different shapes:

* *sphere*: edges xyz = 0
* *box*: radii xyz = 0
* *circle*: radius y = 0, edges xyz = 0
* *plane*: radii xyz = 0, edge y = 0
* *cylinder*: radius y = 0, edges xz = 0
* *rounded* cuboid: radii x = y = z set to small value
* *capsule*: radii x = y = z, edges xz = 0

At zero-subdivision level it is also possible to create octagonal and hexagonal prisms.

A created octasphere has an edge length of 2 and radius of 1; can be resized afterwards by calling the `reshape(rx, ry, rz, ex, ey, ez)` method on it. The first three arguments set the radii across three dimensions, the last three arguments set the edge lengths.

```Lua
octa2 = solids.octasphere(2)
cylinder = octa2:reshape(1, 0, 1, 0, 2, 0)
capsule  = octa2:reshape(1, 1, 1, 0, 2, 0)
```

Note: unlike other implemented solid primitives, octasphere's adjacent faces do share the same vertices.


### Converting meshes to solid object

Besides creating a primitive solid from scratch, it is also possible to initialize a solid object from data in other formats. They are also useful as intermediate step for using CSG module (described below).

#### solids.new()

Initialize a blank object containing no vertices or indices.

#### solids.fromVertices(vertices, indices)

Construct a *solid* representation from nested list of vertices and list of indices. If indices are not provided the vertices are assumed to be in sequential order.

#### solids.fromModel(model)

Use LOVR's internal model structure (which can be loaded from a file) to initialize the solid. This is a lossy operation as only the triangle geometry will be preserved. In particular the original normals would not be preserved and they are replaced by computed normals.

#### solids.fromMesh(mesh)

Construct a solid from LOVR's Mesh object. Returns a solid with the mesh's vertices and indices.

#### solids.fromModelSlice(model, index)

Construct a solid from LOVR's Mesh object, handling a mesh that is subset of another. Useful for models with multiple meshes.

#### solids.fromConvexShape(shape)

Extract convex hull from LOVR's ConvexShape object. Returns a solid with vertices and indices extracted from the shape.

#### solids.fromCurve(curve, width, n, DTS)

Create a solid shape from a curve. The curve is subdivided into `n` segments (default 32) and extruded by `width` (default 1).

#### solids.fromCSG(csg)

Convert the CSG geometry (see below) to solids geometry. This function can be used after all the CSG operations are completed, to render the result or to convert it to other formats.

#### solids.convexHull(point_cloud)

Build up a convex hull from a list of `vec3` points. This will generate a convex mesh whose volume includes all the input points. The points falling inside the hull are discarded, and points on the hull are joined in outward-facing triangles. Input list `point_cloud` is left unmodified.

```Lua
point_cloud = {}
for i = 1, 100 do
  point_cloud[i] = vec3(lovr.math.random(), lovr.math.random(), lovr.math.random())
end
convex_hull = solids.convexHull(point_cloud)
```

### Module utility functions

#### solids.setFormats(vertex_format, index_format)

Sets future buffer format fields; best called upfront on init. Existing solids need to be invalidated manually, for example by replacing them with `:clone()`.

#### solids.linePointDistance(line, point)

Distance of a point vector from a line segment formed from two vectors.

#### solids.trianglePointDistance(triangle, point)

Distance of a point vector from a triangle formed from three vectors. If positive, the point is in front of the triangle. If zero, point and triangle are coplanar. If negative, the point is behind the triangle.

#### solids.barycentric(triangle, point)

Returns barycentric coordinates of a point on a triangle. Returns `nil` if the point is not on the triangle plane or if the triangle is degenerate.

#### solids.sewindices(edgeA, edgeB, offsetA, offsetB)

Create list of indices that sews together two lists of indices. Constructs triangles between edges A and B, similar to triangle strip.

#### solids.merge(solidsList)

Combine triangles from two or more solids into a merged solid. Takes a list of solids and returns a single merged solid.

```Lua
merged = solids.merge({solidA, solidB, solidC})
```

### Operators on solid shapes

All the operations are immutable; they preserve the originals while creating and returning the new solid objects. The only exception is `updateNormals()` which modifies the solid it is called upon.

#### solid:transform(transform, side_filter)

Used to displace, rotate or scale mesh vertices by applying Mat4 parameter to each. If `side_filter` table is specified, only vertices with indices listed in this table will be affected.

```Lua
cube_solid = solids.cube()
cube_solid = cube_solid:transform(mat4(0,0,0,  2,2,2)) -- double the cube size
cube_solid = cube_solid:transform(mat4(0,0,0,  0.5, 1, 0.5), cube_solid.sides.top) -- shrink the top side
```

#### solid:map(fn, side_filter)

Iterates over all vertices to process them; calls the passed callback function that can modify the vertex information.

```Lua
quad_solid = solids.quad(6)  -- subdivided plane with 6x6 squares
quad_solid:map(
  function(x, y, z) 
    z = (lovr.math.noise(x, y) - 0.5) * 2
    return x, y, z
  end)
```

#### solid:subdivide()

Creates a new mesh with 4x times more geometry than original mesh, while preserving the shape. Each triangle is subdivided into four triangles. The generated triangles don't share any vertices between them. This operation can be used before the mesh is further processed by `map` function, to increase the fidelity of result.

```Lua
mesh = solids.bipyramid(3)     -- 18 vertices
mesh = mesh:subdivide()        -- 72 vertices
```

#### solid:clone()

Create new solid identical to the existing one. All vertex and index data is copied.

#### solid:scale(vec3_or_sx, sy, sz)

Create a solid by scaling each vertex. Can accept a vec3, a table, or individual scale values. If only `sx` is provided, uniform scaling is applied.

```Lua
cube = solids.cube()
scaled = cube:scale(2, 1, 0.5)  -- scale differently on each axis
scaled = cube:scale(2)          -- uniform scaling
```

#### solid:mergeIn(solid_or_list)

Combines triangles from one or more solids into this solid, modifying it in-place. Returns the modified solid. Takes either a single solid or a list of solids.

```Lua
solidA:mergeIn(solidB)
solidA:mergeIn({solidB, solidC})
```

#### solid:separateFaces()

Create a solid with no vertices shared between the two faces. If vertices are shared between two triangles, the normals get interpolated and the lighting will look incorrect; neighbor triangles will blend into each other as if the surface is smooth. This operation ensures each triangle has its own vertices.

#### solid:filterTriangles(predicate)

Create a solid with only the triangles that pass the predicate function. The predicate receives three vertices (a, b, c) and should return `true` to keep the triangle.

```Lua
filtered = solid:filterTriangles(function(a, b, c)
  return a[2] > 0  -- keep only triangles with first vertex above y=0
end)
```

#### solid:clean()

Remove degenerate triangles from the solid. A triangle is degenerate if its cross product length is below a threshold.

#### solid:updateNormals()

Function calculates *normal* vectors for each triangle and stores them into vertex data. This is often needed inside shaders for surface lighting and other effects.

First, a normal of each triangle is determined and added to each affected vertex, after that each vertex averages all the normal vectors it has acquired in the first pass, to smooth them out. This is relevant only for meshes imported from models and for octasphere; all other solid primitives are built with triangles that don't reuse any vertices.

This operation is best done after all vertex manipulations are done. It is automatically called as needed inside the `solid:draw()` function. Modifies the input solid in-place.

#### solid:flipWinding()

Creates a solid in which triangles have the flipped vertex order (opposite winding). This reverses the face normals.

#### solid:setColor(r_or_table_or_vec, g, b, a)

Set the color of all vertices in the solid. Can accept individual RGBA values, a table, or a vec3/vec4. RGB values are converted from gamma to linear space.

```Lua
solid = solids.cube()
red_solid = solid:setColor(1, 0, 0)
blue_solid = solid:setColor({0, 0, 1})
green_solid = solid:setColor(vec3(0, 1, 0))
```

#### solid:bakeFill(...)

Bakes additional data into all the vertices. Assumes that the first 6 vertex data are position and normal. Any other vertex data (material information, baked lighting) would go after and can be modified. This function applies same data to all the vertices.

```Lua
solid = solids.sphere(2)
solid = solid:bakeFill(1, 0.5, 0.2)  -- bake r, g, b values
```

#### solid:bendOnCurve(curve_ref, curve_tgt, up, curve_subdivisions)

Distort the solid from reference curve shape to target curve shape. Maps mesh vertices to the closest ref curve points and applies transforms to bend the mesh along the target curve.

#### solid:makeOutline(amount, color)

Creates an outline solid by offsetting faces along their normals. The `amount` parameter controls the offset distance (default 0.03), and `color` sets the outline color (default {0.1, 0.1, 0.1}).

```Lua
outline = solids.cube():makeOutline(0.05, {0, 0, 0})
```

#### solid:addOutline(amount, color)

Adds an outline (scaled-up, face-winding reversed, colored) to the solid. Returns same solid that contains the original solid and the outline.

```Lua
cube_with_outline = solids.cube():addOutline(0.03, {0.1, 0.1, 0.1})
```

#### solid:mergeTrianglesIntoPolygons(precision)

Identify triangles facing same way, merge into polygons. Returns faces, which is a list of lists of indices. The `precision` parameter (default 0.01) controls normal comparison tolerance.

#### solid:jiggleNormals(amount)

Create a solid with randomized normals. Adds random offset to each normal vector, useful for stylized rendering effects.

#### solid:raycast(start, stop, doublesided)

Cast a ray and return list of intersection points with the solid. Uses Möller-Trumbore algorithm. If `doublesided` is true, intersects both front and back faces.

```Lua
intersections = solid:raycast(vec3(0, 0, 0), vec3(1, 0, 0), false)
```

#### solid:centerOfMass()

Returns the center of mass of the solid as a vec3.

#### solid:volume()

Returns the volume of the solid.

#### solid:info()

Get a string with basic info about solid (vertex count, index count, volume, center of mass).

#### solid:invalidate()

Remove the internal buffer representation of solid to force the refresh. Sets the mesh to `nil`.

#### solid:calculateBoundingBox()

Calculate and set the bounding box for the mesh. Returns minx, maxx, miny, maxy, minz, maxz.

#### solid:refresh()

Regenerate the mesh object from vertices and indices. Automatically calls `updateNormals()` if needed and calculates the bounding box.

#### solid:toObjString()

Convert the solid to OBJ file format string. Includes vertices, normals, and faces.

#### solid:draw(pass, ...)

Used to render the solid mesh inside the pass. Optional transform arguments can be supplied as mat4 object or as set of numerical values; any other arguments supported by `Pass:mesh()` can also be used (start, count, instances).

The function automatically computes normals and constructs the vertex and index buffers needed for rendering the mesh.

```Lua
sphere = solids.sphere(2) -- be careful with subdivisions > 4 as geometry count explodes

function lovr.draw(pass)
  sphere:draw(pass, 0, 2, -2)  -- draw at 0, 2, -2 coordinates
end
```

#### solid:triangleToLine(threshold)

Creates a solid in which all the triangles are replaced with lines. The internal flat list of triangle indices is converted to a flat list of line indices. Edges shared between triangles are not repeated. The `threshold` parameter (default 0) controls the minimum angle between face normals to include an edge. Such solid can be rendered as a wireframe after `pass:setMeshMode('lines')` is set (this is *not* automatically handled by the `draw()` method).

The intended use is to support custom drawing methods which can give a special treatment to edges.

```Lua
solid = solids.tcube(0.7):triangleToLine()

function lovr.draw(pass)
  for i = 1, #solid.ilist, 2 do -- draw a capsule between each two points
    local i1, i2 = solid.ilist[i], solid.ilist[i + 1]
    local v1, v2 = solid.vlist[i1], solid.vlist[i2]
    pass:capsule(vec3(unpack(v1)), vec3(unpack(v2)), 0.02, 8)
  end
end
```

#### solid:getConnections()

Returns a map of connections between vertex indices in a solid that can be used to gain insight into the mesh.

```Lua
solid = solids:cylinder(5)
graph = solid:getConnections()

-- check if vertices #1 and #2 are connected
if graph[1][2] then
end

-- iterate over all vertices connected to 2
for vi, _ in pairs(graph[2]) do
  local vertex = solid.vlist[vi]
  -- process the vertex
end
```

#### solid:debugDraw(pass, ...)

Visualizes the solid shape in a wireframe mode, together with face normals. This is useful for inspection of meshes during development.