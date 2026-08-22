# =============================================================
# icon_maker.gd — the app icon, sculpted by the game itself.
# -------------------------------------------------------------
# Run:  ./tools/icon.sh
#
# WHY THIS EXISTS: iOS will not ship without a 1024x1024 PNG app
# icon, and this project deliberately contains no image files at
# all. Rather than break that rule with a hand-drawn PNG that
# would slowly drift out of step with the art, the icon is
# rendered from the same two mesh generators and the same shader
# as everything else. Re-run it after a palette change and the
# icon follows.
#
# It builds its own little scene rather than photographing the
# world, because an icon needs a clean background, a tight square
# crop and a camera nowhere near the one the game plays on.
#
# Apple wants no transparency and no rounded corners -- iOS draws
# the rounded mask itself -- so this fills the frame edge to edge.
# =============================================================
extends Node

const OUT := "res://icon_1024.png"


func run() -> void:
	var root := Node3D.new()
	add_child(root)

	# A flat warm ground and sky, so the silhouette reads at 60 px.
	# A busy background is the single most common way a game icon
	# becomes an unrecognisable smudge on a home screen.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.SKY_BLUE.lerp(Palette.CREAM, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.AMBIENT_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.7
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Palette.SUN_COLOR
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-34, 132, 0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Palette.AMBIENT_SKY
	fill.light_energy = 0.3
	fill.rotation_degrees = Vector3(-24, -50, 0)
	root.add_child(fill)

	# A disc of grass for the pair to stand on, so they are not
	# floating in the sky.
	var ground := ClayKit.blob(Vector3(6.4, 1.5, 6.4), Palette.MOSS,
		Vector3(0, -0.95, 0), {"segments": 22, "grain": 0.14})
	root.add_child(ground)

	# The village landmark, which is the most recognisable shape in
	# the game, with the Sprite in front of it for scale and a face.
	var cap := Props.landmark_mushroom()
	cap.position = Vector3(0.35, -0.2, -1.2)
	cap.rotation_degrees.y = 18.0
	root.add_child(cap)

	var sprite := Props.sprite_body()
	sprite.position = Vector3(-1.05, -0.25, 2.1)
	# Facing the lens. Godot forward is -Z and the face is sculpted on
	# -Z, so a half turn puts it toward a camera on +Z.
	sprite.rotation_degrees.y = 195.0
	sprite.scale = Vector3.ONE * 1.62
	root.add_child(sprite)

	var cam := Camera3D.new()
	# Tight. An icon is looked at 60 pixels wide on a home screen, so
	# the subject fills the frame and the background is a sliver --
	# the first pass framed it like a photograph and the Sprite was
	# a dot.
	cam.fov = 38.0
	cam.position = Vector3(0.85, 1.95, 4.25)
	cam.look_at_from_position(cam.position, Vector3(-0.05, 1.30, 0.0), Vector3.UP)
	root.add_child(cam)
	cam.make_current()

	# Let the meshes build and the shadow map settle before the shot.
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	# Square, whatever the window did. Centre crop rather than squash:
	# a stretched Sprite looks wrong in a way people notice without
	# being able to say why.
	# Centre crop to a square, then trim a further margin. The camera
	# gets most of the way there; this takes out the last of the sky
	# so the subject really does fill the tile.
	var side: int = int(mini(img.get_width(), img.get_height()) * 0.86)
	img = img.get_region(Rect2i(
		(img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	# No alpha channel: Apple rejects icons with transparency.
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OUT)
	print("[icon] wrote ", ProjectSettings.globalize_path(OUT),
		" (%dx%d, no alpha)" % [img.get_width(), img.get_height()])
	get_tree().quit()
