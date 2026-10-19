extends SceneTree
## ResourceLoader dependency metadata includes binary .res; does not load the full level.
func _initialize():
 run.call_deferred()
var graph:Dictionary={}
func scan(path:String):
 var dir=DirAccess.open(path)
 if dir==null:return
 for file in dir.get_files():
  if file.get_extension() in ["tscn","tres","res","glb","gltf","gd","gdshader","png","jpg","jpeg","svg","ogg","wav","ogv"]:
   var p=path.path_join(file)
   var deps:Array=[]
   for dep in ResourceLoader.get_dependencies(p):
    var parts=dep.split("::");deps.append(parts[parts.size()-1])
   graph[p]=deps
 for folder in dir.get_directories():scan(path.path_join(folder))
func run():
 scan("res://assets");scan("res://scenes");scan("res://scripts")
 DirAccess.make_dir_recursive_absolute("res://tools/.local")
 var f=FileAccess.open("res://tools/.local/runtime_resource_graph.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(graph));f.close()
 print("GRAPH ",graph.size());quit()
