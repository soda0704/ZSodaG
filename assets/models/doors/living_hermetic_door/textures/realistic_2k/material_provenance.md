# Material sources and processing

User reference files: frame_basecolor.png and doors_basecolor.png, copied without changing the desktop originals to reference_frame_color.png and reference_doors_color.png. Interior color/texture samples are used as material references, not as projected pictures of the door. The provided mismatched normal, roughness, metallic and AO images are not used in the final PBR set.

Microheight source generated with the built-in imagegen tool. No CLI or external API fallback was used. Output saved locally as paint_microheight_source.png. It is a source for material sampling, not an additional runtime texture.

Generation prompt:

> Create a single seamless tileable grayscale micro-height texture for physically based industrial powder-coated steel, square 2048x2048. This is a raw technical material texture, not a product photograph: perfectly flat uniform diffuse illumination, no lighting gradients, no highlights, no shadows, no objects, no panel outlines, no bolts, no text, no borders. Neutral mid gray overall. Very fine irregular orange-peel powder-coat grain, submillimeter stippling, sparse tiny pores, subtle fine linear abrasion scratches in varied directions, a few restrained clusters of shallow pitting. Multi-scale natural physically plausible surface microstructure with excellent crisp detail, fine rather than coarse rocks. No large stains, no cracks, no corrosion patterns. Height values centered around middle gray with restrained contrast; brighter raised paint grain and darker shallow scratches. Seamless boundaries. Intended as common microheight source for coherent 2K PBR texture baking of a near-future arctic industrial door. Output the texture only.

The generated source was 1254 × 1254; all final maps are independently rasterized at 2048 × 2048. Geometry-dependent wear is computed from physical edge distances and shared deterministic masks. Tangent-space normals are derived from physical-height gradients using measured UV texel density. Albedo, ORM and normal use the same atlas coordinates, with 12-pixel gutter dilation. The height source is not multiplied into albedo as directional lighting.

Runtime files: frame_basecolor.png, frame_Normal.png, frame_ORM.png, doors_basecolor.png, doors_Normal.png, doors_ORM.png. ORM channels: R occlusion, G roughness, B metallic. Height files are auxiliary maps, not displacement geometry. All six runtime textures are embedded in the exported GLB.
