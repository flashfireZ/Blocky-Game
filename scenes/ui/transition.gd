extends CanvasLayer

@onready var rect = $ColorRect

func _ready():
	rect.modulate.a = 0


func change_scene(scene_path):

	await fade_out()

	get_tree().change_scene_to_file(scene_path)

	await fade_in()


func fade_out():

	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, 0.3)

	await tween.finished


func fade_in():

	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, 0.3)

	await tween.finished
