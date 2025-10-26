The repository is a collection of Lua libraries for creating triangle meshes from scratch and for constructing more complex objects from geometric primitives.

The intended use is for constructing low-polygon 3D meshes that can then be dynamically adapted during runtime. It also features generating points in a layout that can be used for procedural placement objects on the scene. The whole procmesh library leverages the Lua's interpreted nature to  enable iterative 3D modeling in live-coding fashion.

Code is designed to be used within [LÖVR](https://github.com/bjornbytes/lovr) framework and partially depends on LOVR built-in vector math library. With simple substitution of vector and mesh data structures the code could be used elsewhere. Libraries have no inter-dependencies so they can be used separately, and they can be combined to chain complex operations.

### Documentation & examples

Each module has a separate document with API and examples. Please refer to them to check for features of each module.

[dots.lua](dots.md) creates, draws and manipulates a point cloud (grid, random samplings, pruning, symmetries, merging)

[solids.lua](solids.md) creates or imports meshes primitives, draws them, algorithms to manipulate the mesh data

[csg.lua](csg.md) constructive solid geometry implementations of add, sub & intersect operations on mesh objects

This repository summary document will provide examples of overall use, to learn the usage and demonstrate combining of individual modules.





## License

The code in repository is under MIT license.

The sphere generation uses [lovr-icosphere](https://github.com/bjornbytes/lovr-icosphere) code under MIT license.

The csg algorithm originates from [https://github.com/evanw/csg.js](https://github.com/evanw/csg.js) code under MIT license.