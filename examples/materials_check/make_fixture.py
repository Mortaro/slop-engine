"""Writes materials.blend: one small plane per material feature the scene renderer reads.

Run with Blender 5.2 in background mode:
    blender --background --factory-startup --python make_fixture.py
"""
import os
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 16


def image(name, colour, non_color=False, pattern=None):
    made = bpy.data.images.new(name, SIZE, SIZE, alpha=True)
    if non_color:
        made.colorspace_settings.name = 'Non-Color'
    pixels = []
    for row in range(SIZE):
        for column in range(SIZE):
            value = pattern(column, row) if pattern else colour
            pixels.extend(value)
    made.pixels = pixels
    made.pack()
    return made


def ring_texel(column, row):
    across = column + 0.5 - SIZE / 2
    down = row + 0.5 - SIZE / 2
    distance = (across * across + down * down) ** 0.5
    inside = 4.5 < distance < 7.5
    return (1.0, 0.1, 0.1, 1.0 if inside else 0.0)


def material(name):
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    return made


def principled(made):
    return made.node_tree.nodes['Principled BSDF']


def image_node(made, picture):
    node = made.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = picture
    return node


def link(made, from_socket, to_socket):
    made.node_tree.links.new(from_socket, to_socket)


def plane(name, made, x, y, z=0.0, flipped=False):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(x, y, z))
    placed = bpy.context.active_object
    placed.name = name
    placed.data.name = name
    if flipped:
        placed.rotation_euler = (3.14159265, 0.0, 0.0)
    placed.data.materials.append(made)
    return placed


def base_image(made, picture):
    node = image_node(made, picture)
    link(made, node.outputs['Color'], principled(made).inputs['Base Color'])
    return node


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    grey = image('grey', (0.5, 0.5, 0.5, 1.0))

    plain = material('Plain')
    base_image(plain, grey)
    plane('Plain', plain, -4.5, 0.0)

    for side, tilt in (('Right', 0.8), ('Left', 0.2)):
        bumpy = material('Bump' + side)
        base_image(bumpy, grey)
        normal_picture = image('normal_' + side.lower(), (tilt, 0.5, 0.9, 1.0), non_color=True)
        normal_node = image_node(bumpy, normal_picture)
        mapping = bumpy.node_tree.nodes.new('ShaderNodeNormalMap')
        mapping.inputs['Strength'].default_value = 1.0
        link(bumpy, normal_node.outputs['Color'], mapping.inputs['Color'])
        link(bumpy, mapping.outputs['Normal'], principled(bumpy).inputs['Normal'])
        plane('Bump' + side, bumpy, -3.0 if side == 'Right' else -1.5, 0.0)

    metal = material('Metal')
    base_image(metal, grey)
    packed = image('occlusion_roughness_metallic', (1.0, 0.2, 1.0, 1.0), non_color=True)
    packed_node = image_node(metal, packed)
    split = metal.node_tree.nodes.new('ShaderNodeSeparateColor')
    link(metal, packed_node.outputs['Color'], split.inputs['Color'])
    link(metal, split.outputs['Green'], principled(metal).inputs['Roughness'])
    link(metal, split.outputs['Blue'], principled(metal).inputs['Metallic'])
    principled(metal).inputs['Specular IOR Level'].default_value = 0.25
    plane('Metal', metal, 0.0, 0.0)

    glow = material('Glow')
    base_image(glow, grey)
    glow_picture = image('glow', (1.0, 0.25, 0.0, 1.0))
    glow_node = image_node(glow, glow_picture)
    link(glow, glow_node.outputs['Color'], principled(glow).inputs['Emission Color'])
    principled(glow).inputs['Emission Strength'].default_value = 4.0
    plane('Glow', glow, 1.5, 0.0)

    unlit = material('Unlit')
    tree = unlit.node_tree
    tree.nodes.remove(principled(unlit))
    emission = tree.nodes.new('ShaderNodeEmission')
    emission.inputs['Strength'].default_value = 2.0
    unlit_picture = image('unlit', (0.0, 1.0, 0.0, 1.0))
    unlit_node = image_node(unlit, unlit_picture)
    link(unlit, unlit_node.outputs['Color'], emission.inputs['Color'])
    link(unlit, emission.outputs['Emission'], tree.nodes['Material Output'].inputs['Surface'])
    plane('Unlit', unlit, 3.0, 0.0)

    one_sided = material('OneSided')
    base_image(one_sided, grey)
    one_sided.use_backface_culling = True
    plane('OneSided', one_sided, 4.5, 0.0, flipped=True)

    two_sided = material('TwoSided')
    base_image(two_sided, grey)
    plane('TwoSided', two_sided, 4.5, -1.5, flipped=True)

    white = image('white', (1.0, 1.0, 1.0, 1.0))
    backdrop = material('Backdrop')
    base_image(backdrop, white)
    plane('Backdrop', backdrop, -4.5, -1.5)

    glass = material('Glass')
    blue = image('blue', (0.0, 0.0, 1.0, 1.0))
    base_image(glass, blue)
    glass.surface_render_method = 'BLENDED'
    principled(glass).inputs['Alpha'].default_value = 0.5
    plane('Glass', glass, -4.5, -1.5, 0.25)

    ring_picture = image('ring', None, pattern=ring_texel)
    ring = material('Ring')
    tree = ring.node_tree
    tree.nodes.remove(principled(ring))
    clear = tree.nodes.new('ShaderNodeBsdfTransparent')
    glowing = tree.nodes.new('ShaderNodeEmission')
    glowing.inputs['Strength'].default_value = 2.0
    ring_node = image_node(ring, ring_picture)
    link(ring, ring_node.outputs['Color'], glowing.inputs['Color'])
    mix = tree.nodes.new('ShaderNodeMixShader')
    link(ring, ring_node.outputs['Alpha'], mix.inputs['Fac'])
    link(ring, clear.outputs['BSDF'], mix.inputs[1])
    link(ring, glowing.outputs['Emission'], mix.inputs[2])
    link(ring, mix.outputs['Shader'], tree.nodes['Material Output'].inputs['Surface'])
    ring.surface_render_method = 'BLENDED'
    plane('Ring', ring, 6.0, 0.0)

    stripes = image('stripes', None, pattern=lambda column, row: (1.0, 1.0, 1.0, 1.0) if column < SIZE // 2 else (0.0, 0.0, 0.0, 1.0))
    scroll = material('Scroll')
    base_image(scroll, stripes)
    plane('Scroll', scroll, -3.0, -1.5)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'materials.blend'), compress=True)


main()
