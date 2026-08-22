# =============================================================
# plugin.gd — registers the iOS Info.plist injector.
# -------------------------------------------------------------
# Editor-only. Costs the shipped game nothing; it does not even
# exist at runtime.
# =============================================================
@tool
extends EditorPlugin

var _exporter: EditorExportPlugin


func _enter_tree() -> void:
	_exporter = preload("res://addons/ios_plist/export_plugin.gd").new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	if _exporter:
		remove_export_plugin(_exporter)
		_exporter = null
