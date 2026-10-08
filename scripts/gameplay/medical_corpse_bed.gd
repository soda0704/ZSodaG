extends Node3D
@export var interaction_distance := 3.0
@export var legacy_bed_path := NodePath()
func _ready() -> void:
 add_to_group("medical_corpse_beds")
func get_interaction_prompt() -> String:
 var player=get_tree().get_first_node_in_group("local_player")
 if is_occupied(): return "Койка занята"
 return "Уложить тело на койку" if player!=null and player.is_carrying_corpse() else "Медицинская койка"
func is_occupied() -> bool:
 var level=get_tree().get_first_node_in_group("expedition_level")
 if level==null: return true
 var path=level.get_path_to(self)
 for corpse in get_tree().get_nodes_in_group("medical_corpses"):
  if corpse.bed_path==path and corpse.mode in [MedicalCorpse.Mode.PLACING,MedicalCorpse.Mode.DELIVERED]: return true
 return false
func network_interact(peer:int,player:Node) -> void:
 if not multiplayer.is_server() or not player is GamePlayer or player.owner_peer_id!=peer or player.survival.dead or not player.is_carrying_corpse() or is_occupied(): return
 if player.global_position.distance_to(global_position)>interaction_distance: return
 player.carried_corpse.place_on_bed(peer,self)
