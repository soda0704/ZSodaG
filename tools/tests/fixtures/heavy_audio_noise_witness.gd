extends Node3D
var heard:Array[Dictionary]=[]
func _ready() -> void:add_to_group("hostile_monsters")
func hear_noise(source:Node3D,point:Vector3,radius:float) -> void:
	heard.append({"source":source,"point":point,"radius":radius})
