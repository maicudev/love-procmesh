# csg

![realtime demo of CSG operations](media/csg.gif "Realtime CSG")

Constructive Solid Geometry is a technique of modeling 3D shapes by adding, subtracting and intersecting meshes. The csg library is implementation of CSG algorithms using efficient binary space partitioning.

The algorithm was originally constructed by Evan Wallace as JS library and ported to Lua by Tobias Teleman. This codebase fixes and improves on Lua code and adapts it to LOVR's data structures by using `lovr.math` vectors. The result can be used in LOVR once the *CSG* object is converted back to *solid* object.


```Lua
csg = require('solids')
csg = require('csg')
csgA = csg.fromSolid(solidA)
csgB = csg.fromSolid(solidB)
csgU = csgA:add(csgB)          -- or with syntax sugar: csgU = csgA + csgB
csgS = csgA:sub(csgB)                                -- csgS = csgA - csgB
csgI = csgA:intersect(csgB)                          -- csgI = csgA * csgB
solidU = solids.fromCSG(csgU)
solidI = solids.fromCSG(csgI)
solidS = solids.fromCSG(csgS)
```

The CSG object can be initialized from a solid object (described above), or from similarly formatted table of vertices and indices. If instancing from custom table, the vertices should be stored in a nested table under key `vlist`, and triangle indices in a flat table under key `ilist`.

The CSG library converts the input to a list of polygons. The union/subtract/intersect operations are immutable - they don't modify input CSG objects, they instead create new CSG object and return it as a result.

Limitations:

 * non-intersecting polygons still generate excess geometry
 * all [issues from original repo](https://github.com/evanw/csg.js/issues) are retained in this implementation
