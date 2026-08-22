# =============================================================
# export_plugin.gd — the one Info.plist key Godot cannot set.
# -------------------------------------------------------------
# WHY THIS EXISTS:
#
# iOS refuses to let an app touch the local network until the
# user agrees, and it will only ask if the app declares WHY, via
# NSLocalNetworkUsageDescription in Info.plist. Without that key
# the iPad fails to join a game with **no error at all** -- no
# timeout, no message, nothing happens. It looks exactly like a
# bug in the game.
#
# Godot 4.7's iOS exporter has privacy fields for camera,
# microphone, photo library and a dozen tracking reasons -- but
# none for local network. So the key has to be added by hand in
# Xcode after every single export, and forgetting once produces
# the least debuggable failure in the whole project.
#
# This adds it automatically instead. It fires on iOS exports
# only and prints a line so you can see that it did.
# =============================================================
@tool
extends EditorExportPlugin

const REASON := "Tendril Hills uses your local network so you can play together with people in this house."


func _get_name() -> String:
	return "TendrilHillsIOSPlist"


func _export_begin(features: PackedStringArray, is_debug: bool,
		path: String, flags: int) -> void:
	if not ("ios" in features):
		return
	add_ios_plist_content(
		"<key>NSLocalNetworkUsageDescription</key>\n<string>%s</string>" % REASON)
	print("[ios_plist] added NSLocalNetworkUsageDescription")
