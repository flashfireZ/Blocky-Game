extends Node2D

func set_color(c: Color):
	# On cherche le noeud. Remplace "ColorRect" par "Block" si c'est son vrai nom !
	var color_rect = get_node_or_null("ColorRect") 
	
	if color_rect != null:
		if color_rect.material != null:
			# 1. On duplique le material pour qu'il soit unique à CE bloc
			var unique_material = color_rect.material.duplicate()
			
			# 2. On change la couleur
			unique_material.set_shader_parameter("base_color", c)
			
			# 3. On applique le nouveau material au bloc
			color_rect.material = unique_material
		else:
			push_error("Pas de material assigné sur le noeud " + color_rect.name)
	else:
		push_error("Le noeud 'ColorRect' est introuvable dans " + name + ". Vérifie l'orthographe !")
