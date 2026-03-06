extends Node


# --- RESSOURCES ---
var stars: int = 0
var apples: int = 100 # Un peu de budget pour tester

const STAR_TO_APPLE_RATE = 2000
# --- BÂTIMENTS ---
# Ce tableau va contenir des dictionnaires : { "path": "res://...", "x": 10, "z": -4 }
var placed_buildings_data: Array = []

func _ready():# On charge dès le lancement du jeu
	load_game()
	print(OS.get_user_data_dir())
	
# --- FICHIER DE SAUVEGARDE ---
const SAVE_PATH = "user://savegame.json"

signal resources_updated



# --- GESTION DES RESSOURCES ---
func add_stars(amount: int):
	stars += amount
	save_game() # On sauvegarde à chaque gain important
	resources_updated.emit()

func spend_apples(amount: int) -> bool:
	if apples >= amount:
		apples -= amount
		save_game()
		resources_updated.emit()
		return true
	return false

# --- GESTION DES BÂTIMENTS ---
func add_building(scene_path: String, position: Vector3):
	# On crée une "fiche" pour ce bâtiment
	var data = {
		"scene_path": scene_path,
		"x": position.x,
		"z": position.z
		# Tu pourras ajouter ici : "level": 1, "last_collection_time": ...
	}
	placed_buildings_data.append(data)
	save_game()

func remove_building(position: Vector3):
	# Pour plus tard : si on vend un bâtiment, on le cherche par sa position et on le supprime
	pass

# --- SYSTEME DE SAUVEGARDE (JSON) ---
func save_game():
	var save_dict = {
		"stars": stars,
		"apples": apples,
		"buildings": placed_buildings_data
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_dict)
		file.store_string(json_string)
		# print("Sauvegarde effectuée.")

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("Aucune sauvegarde trouvée. Nouvelle partie.")
		return # On garde les valeurs par défaut
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var data = json.get_data()
			# On remet les valeurs en mémoire
			stars = data.get("stars", 0)
			apples = data.get("apples", 100)
			placed_buildings_data = data.get("buildings", [])
			
			resources_updated.emit()
			print("Sauvegarde chargée avec succès !")
		else:
			print("Erreur de lecture du fichier JSON")

func convert_stars_to_apples():
	if stars >= STAR_TO_APPLE_RATE:
		var apples_to_add = stars / STAR_TO_APPLE_RATE
		apples += apples_to_add
		stars = stars % STAR_TO_APPLE_RATE # On garde le reste
		resources_updated.emit()
		print("Conversion réussie ! Pommes: ", apples)
		return true
	return false
