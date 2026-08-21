# =============================================================
# bench.gd — dev tool: how heavy is the world, really?
# -------------------------------------------------------------
# Run:  ./tools/bench.sh
# Raw:  godot --path . --rendering-driver opengl3 -- --bench
#
# Prints node count, mesh-instance count, static-body count, and
# the average frame time over a few seconds of standing in the
# village. Growing the world is the kind of change that is easy
# to ship and hard to un-ship, so measure before and after.
# =============================================================
extends Node

var _main: Node3D
var _frames := 0
var _accum := 0.0
var _worst := 0.0
var _warmup := 10


func setup(main: Node3D) -> void:
	_main = main
	await get_tree().create_timer(1.5).timeout
	_report_counts()
	set_process(true)


func _report_counts() -> void:
	var nodes := 0
	var meshes := 0
	var bodies := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		if n is MeshInstance3D:
			meshes += 1
		if n is StaticBody3D or n is CollisionShape3D:
			bodies += 1
		for c in n.get_children():
			stack.append(c)
	print("[bench] nodes=%d meshes=%d colliders=%d interactables=%d" % [
		nodes, meshes, bodies, _main.world.interactables.size()])
	print("[bench] half_size=%.1f  area=%.0f m2" % [
		Terrain.HALF_SIZE, pow(Terrain.HALF_SIZE * 2.0, 2)])


func _process(delta: float) -> void:
	if _warmup > 0:
		_warmup -= 1
		return
	_frames += 1
	_accum += delta
	_worst = maxf(_worst, delta)
	if _frames >= 60:
		var avg := _accum / float(_frames) * 1000.0
		# The number that actually decides whether this runs on a
		# laptop. Frame time here is measured on whatever machine you
		# are on (and in CI, on a software renderer, where it means
		# nothing) — but draw calls per frame is a property of the
		# scene, not the hardware, and it is what the Compatibility
		# renderer runs out of first.
		var drawn := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var calls := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("[bench] drawn_objects=%d draw_calls=%d triangles=%d" % [
			drawn, calls, prims])
		print("[bench] avg_frame=%.2f ms (%.0f fps)  worst=%.2f ms" % [
			avg, 1000.0 / avg, _worst * 1000.0])
		print("[bench] done")
		get_tree().quit()
