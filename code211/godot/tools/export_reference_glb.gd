extends SceneTree
## Экспорт процедурных моделей в .glb — эталон для художника и проверка пути импорта.
##   godot --headless -s res://tools/export_reference_glb.gd -- <папка>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://reference_glb"
	DirAccess.make_dir_recursive_absolute(out)
	for kind in ["cop", "bandit_light", "bandit_medium", "bandit_heavy", "cashier", "customer"]:
		var root := Node3D.new()
		root.name = kind
		get_root().add_child(root)
		var rig := CharacterRig.new()
		rig.name = "Rig"
		root.add_child(rig)
		rig.setup(kind)
		_bake_rotation_tracks(rig.anim)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(root, state)
		if err == OK:
			err = doc.write_to_filesystem(state, out.path_join(kind + ".glb"))
		print("%s -> %s" % [kind, error_string(err)])
		root.queue_free()
	quit()


## glTF хранит только TRS-треки: переводим value-треки ":rotation" (эйлер) в ROTATION_3D (кватернионы).
func _bake_rotation_tracks(ap: AnimationPlayer) -> void:
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var a := lib.get_animation(anim_name)
			for t in range(a.get_track_count() - 1, -1, -1):
				var path := str(a.track_get_path(t))
				if a.track_get_type(t) != Animation.TYPE_VALUE:
					continue
				var node_path := path.split(":")[0]
				if path.ends_with(":rotation"):
					var nt := a.add_track(Animation.TYPE_ROTATION_3D)
					a.track_set_path(nt, NodePath(node_path))
					for k in a.track_get_key_count(t):
						var e: Vector3 = a.track_get_key_value(t, k)
						a.rotation_track_insert_key(nt, a.track_get_key_time(t, k), Basis.from_euler(e).get_rotation_quaternion())
					a.remove_track(t)
				elif path.ends_with(":position:y"):
					var pt := a.add_track(Animation.TYPE_POSITION_3D)
					a.track_set_path(pt, NodePath(node_path))
					for k in a.track_get_key_count(t):
						a.position_track_insert_key(pt, a.track_get_key_time(t, k), Vector3(0, float(a.track_get_key_value(t, k)), 0))
					a.remove_track(t)
