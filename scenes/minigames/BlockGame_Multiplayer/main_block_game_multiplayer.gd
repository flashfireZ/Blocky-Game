extends Node2D

@onready var lbl_opponent : Label = $OpponentLabel

func _ready():
	FirebaseManager.setup_scene_refs()
	lbl_opponent.text = "VS  " + FirebaseManager.opp_pid
