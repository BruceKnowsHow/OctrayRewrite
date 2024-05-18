Source code for Octray Rewrite.

Main improvements over [regular Octray](https://github.com/BruceKnowsHow/Octray):
- Sparse octree at the chunk level, so chunks are sparsely allocated ([commit](https://github.com/BruceKnowsHow/OctrayRewrite/commit/829f8c9061bae7826589f6b1898990a4d6492b71))
- Branchless terminating path-tracer using a ray-queue
  - Fast, but approximate since it drops rays when the queue size is small. In practice this doesn't cause visible bugs because it only happens to rays that have bounced many times (due to breadth-first traversal of rays)
  - Most of it can be found in [this file](https://github.com/BruceKnowsHow/OctrayRewrite/blob/5b62eb7212ae6a7ba63f940e1aa78850265783f9/shaders/includes/Raybuffer.glsl)
  - Uses warp intrinsics on Nvidia, otherwise it is very slow. (I couldn't get wave intrinsics to work on AMD)
- Quadtree parallax, to optimize for very high resolution textures ([commit](https://github.com/BruceKnowsHow/OctrayRewrite/commit/56c3fd167c8d1951f24df3396f78188d707f0438))
- Parallax silhouettes ([commit](https://github.com/BruceKnowsHow/OctrayRewrite/commit/ffd0d9e77f51125a8d8cb9d14e9da3c7d9147fb6))
