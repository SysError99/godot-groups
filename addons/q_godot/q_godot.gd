extends Node


const _BOUND_QUERIES = "#BQN"
const _REGISTERED_SCENE = "#RS"
const _SHARED_VAR = 1
const _SYSTEM_CLASS = 0
const _UNREGISTERED_SCENE = "registered_scene"


class Query extends Object:
	var component_names := []
	var parent_class_name := ""
	var subscribers := []
	func add_subscriber(new_subscriber: Array) -> void:
		subscribers.push_back(new_subscriber)


class HalfQueryReference extends Object:
	var q_godot: Object
	var first_half := []
	var second_half := []
	func _init(obj: Object) -> void:
		q_godot = obj
	func iterate() -> Array:
		if q_godot.get("switch"):
			return first_half
		else:
			return second_half


signal query_ready()
signal query_added(query_name)
signal added_to_query(query_name, binds)
signal removed_from_query(query_name, binds)


var switch := false


var _queries := {}
var _query_cache := {}
var _query_half_cache := {}
var _root: Viewport
var _scene_changing := true


# Bind a query to an object or an instantiable object. If you bind a query to instantiated object, 'shared' parameter will be function name string.
func bind_query(parent_class_name: String, component_names: Array = [], system: Object = null, shared = null) -> void:
	var query_name := __get_query_name(parent_class_name, component_names)
	var query_obj: Query
	if query_name in _queries:
		query_obj = _queries[query_name]
	else:
		if not query_name in _query_cache:
			_query_cache[query_name] = []
		if _scene_changing:
			yield(self, "query_ready")
		if not query_name in _queries:
			query_obj = Query.new()
			query_obj.component_names = component_names
			query_obj.parent_class_name = parent_class_name
			_queries[query_name] = query_obj
			emit_signal("query_added", query_name)
			for scene in get_tree().get_nodes_in_group(_REGISTERED_SCENE):
				for entity in scene.get_children():
					__bind_to_query_object(entity, query_name, parent_class_name, component_names)
		else:
			query_obj = _queries[query_name]
	if is_instance_valid(system):
		var new_subscriber := [system, shared]
		var subscribers := [ new_subscriber ]
		query_obj.add_subscriber(new_subscriber)
		for entity_ref in _query_cache[query_name]:
			__bind_to_systems(entity_ref, query_name, subscribers)


# Obtain a query array.
func query(parent_class_name: String, component_names: Array = []) -> Array:
	var query_name := __get_query_name(parent_class_name, component_names)
	if query_name in _query_cache:
		return _query_cache[query_name]
	bind_query(parent_class_name, component_names)
	return _query_cache[query_name]


# Obtain a half-iteratable query.
func query_half(parent_class_name: String, component_names: Array = []) -> HalfQueryReference:
	var query_name := __get_query_name(parent_class_name, component_names)
	if  query_name in _query_half_cache:
		return _query_half_cache[query_name]
	var query_array := query(parent_class_name, component_names)
	var query_size := query_array.size()
	var query_half_size := query_size / 2
	var q := HalfQueryReference.new(self)
	q.first_half = query_array.slice(0, query_half_size - 1)
	if query_size > 1:
		q.second_half = query_array.slice(query_half_size, query_array.size())
	_query_half_cache[query_name] = q
	return q


# Clean up everything before changing scene, very ideal after finishing QGodot session.
func flush_and_change_scene(path: String) -> void:
	for scene in get_tree().get_nodes_in_group(_REGISTERED_SCENE):
		__remove_entities_from_current_scene(scene)
	for ref in _queries.values:
		ref.free()
	for ref in _query_cache.values:
		ref.clear()
	for ref in _query_half_cache.values:
		ref.first_half.clear()
		ref.second_half.clear()
		ref.free()
	_queries.clear()
	_query_cache.clear()
	_query_half_cache.clear()
	get_tree().change_scene_path(path)


# Change scene with internal function, mandatory to make querying system working properly!
func change_scene(path: String) -> void:
	_scene_changing = true
	var current_scene := get_tree().current_scene
	var inst := (load(path) as PackedScene).instance()
	for scene in get_tree().get_nodes_in_group(_REGISTERED_SCENE):
		__remove_entities_from_current_scene(scene)
	current_scene.queue_free()
	yield(current_scene, "tree_exited")
	_root.set_meta("current_scene", inst)
	_root.call_deferred("add_child", inst)
	get_tree().set_deferred("current_scene", inst)
	yield(inst, "ready")
	_scene_changing = false
	__post_change_scene(inst)


# Register specified node as a scene node.
func register_as_scene(node: Node) -> void:
	node.add_to_group(_REGISTERED_SCENE)
	if node.is_in_group(_UNREGISTERED_SCENE):
		node.remove_from_group(_UNREGISTERED_SCENE)
	if node.is_inside_tree():
		for child_ref in node.get_children():
			__setup_entity(child_ref)
			__bind_to_query_objects(child_ref, true)
	node.connect("child_entered_tree", self, "_entity_entered_scene")
	node.connect("child_exiting_tree", self, "_entity_exiting_scene")


# Add specified node to a group, and perform query bindings.
func add_node_to_group(node: Node, group_name: String) -> void:
	node.add_to_group(group_name)
	if node.has_meta(_BOUND_QUERIES):
		__bind_to_query_objects(node, false)
	else:
		__setup_entity(node)
		__bind_to_query_objects(node, true)


# Remove specified node to a group, and perform query bindings.
func remove_node_from_group(node: Node, group_name: String) -> void:
	node.remove_from_group(group_name)
	var index := 0
	var query_name: String
	var bound_queries := node.get_meta(_BOUND_QUERIES, []) as Array
	while index < bound_queries.size():
		query_name = bound_queries[index]
		if not group_name in query_name:
			index += 1
			continue
		__remove_query_from_entity(node, query_name)
		bound_queries.remove(index)


func __get_query_name(parent_class_name: String, component_names: Array) -> String:
	return parent_class_name + "," + PoolStringArray(component_names).join(",")


func __bind_to_query_objects(entity: Node, new_instance: bool) -> void:
	var query_obj: Query
	var subscribers: Array
	if new_instance:
		for query_name in _queries:
			query_obj = _queries[query_name]
			if __bind_to_query_object(entity, query_name, query_obj.parent_class_name, query_obj.component_names):
				subscribers = query_obj.subscribers
				if subscribers.size() > 0:
					__bind_to_systems(entity, query_name, subscribers)
		return
	var bound_queries := entity.get_meta(_BOUND_QUERIES, []) as Array
	for query_name in _queries:
		if query_name in bound_queries:
			continue
		query_obj = _queries[query_name]
		if __bind_to_query_object(entity, query_name, query_obj.parent_class_name, query_obj.component_names):
			subscribers = query_obj.subscribers
			if subscribers.size() > 0:
				__bind_to_systems(entity, query_name, subscribers)


func __bind_to_query_object(entity: Node, query_name: String, parent_class_name: String, component_names: Array) -> bool:
	if entity.get_class() != parent_class_name:
		return false
	var binds := []
	var component: Node
	var component_path: String
	for component_name in component_names:
		component_path = "$" + component_name
		if entity.has_meta(component_path):
			binds.push_back(entity.get_meta(component_path))
			continue
		component = entity.get_node_or_null(component_name)
		if is_instance_valid(component):
			entity.set_meta(component_path, component)
			binds.push_back(component)
			continue
		if entity.is_in_group(component_name):
			continue
		return false
	entity.set_meta("#" + query_name, binds)
	entity.get_meta(_BOUND_QUERIES).push_back(query_name)
	var cache := _query_cache[query_name] as Array
	if query_name in _query_half_cache:
		if cache.size() % 2 == 0:
			_query_half_cache[query_name].second_half.push_back(entity)
		else:
			_query_half_cache[query_name].first_half.push_back(entity)
	cache.push_back(entity)
	emit_signal("added_to_query", query_name, [ entity ] + binds)
	return true


func __bind_to_systems(entity: Object, query_name: String, subscribers: Array) -> void:
	var binds := entity.get_meta("#" + query_name) as Array
	var ebinds := [ entity ] + binds
	var system_inst: Object
	var system: Object
	for system_ref in subscribers:
		system = system_ref[_SYSTEM_CLASS]
		if system.has_method("new"):
			system_inst = system.callv("new", ebinds)
			entity.connect("tree_exited", system_inst, "queue_free")
			system_inst.set("shared", system_ref[_SHARED_VAR])
			entity.add_child(system_inst)
		else:
			system.callv(system_ref[_SHARED_VAR], ebinds)


func __remove_entities_from_current_scene(scene: Node) -> void:
	if scene.is_in_group("persistent_scene"):
		return
	for entity in scene.get_children():
		for query_name in entity.get_meta(_BOUND_QUERIES):
			__remove_entity_from_query(query_name, entity, entity.get_meta("#" + query_name))


func __remove_query_from_entity(entity: Node, query_name: String) -> void:
	__remove_entity_from_query(query_name, entity, entity.get_meta("#" + query_name))
	entity.remove_meta("#" + query_name)


func __remove_entity_from_query(query_name: String, entity: Node, binds: Array) -> void:
	(_query_cache[query_name] as Array).erase(entity)
	if query_name in _query_half_cache:
		var query_half := _query_half_cache[query_name] as HalfQueryReference
		query_half.first_half.erase(entity)
		query_half.second_half.erase(entity)
	emit_signal("removed_from_query", query_name, [ entity ] + binds)


func __post_change_scene(current_scene: Node) -> void:
	var unregistered_scenes := get_tree().get_nodes_in_group(_UNREGISTERED_SCENE)
	if unregistered_scenes.size() > 0:
		for scn_ref in unregistered_scenes:
			register_as_scene(scn_ref)
	else:
		register_as_scene(current_scene)
	yield(get_tree(), "idle_frame")
	emit_signal("query_ready")


func __setup_entity(entity: Node) -> void:
	var bound_queries := []
	entity.set_meta(_BOUND_QUERIES, bound_queries)
	entity.call_deferred("connect", "child_entered_tree", self, "_entity_component_added", [ entity, bound_queries, ])
	entity.call_deferred("connect", "child_exiting_tree", self, "_entity_component_removed", [ entity, bound_queries, ])


func _entity_entered_scene(entity: Node) -> void:
	yield(entity, "ready")
	if entity.has_meta(_BOUND_QUERIES):
		__bind_to_query_objects(entity, false)
	else:
		__setup_entity(entity)
		__bind_to_query_objects(entity, true)


func _entity_exiting_scene(entity: Node) -> void:
	if _scene_changing:
		return
	for group in entity.get_groups():
		match group[0]:
			"#","$":
				continue
			_:
				for query_name in _query_cache:
					if group in query_name:
						__remove_entity_from_query(query_name, entity, [ entity ])


func _entity_component_added(component: Node, entity: Node, bound_queries: Array) -> void:
	var component_name := component.name
	var query_obj: Query
	for query_name in _queries:
		if query_name in bound_queries:
			continue
		if component_name in query_name:
			query_obj = _queries[query_name]
			if __bind_to_query_object(entity, query_name, query_obj.parent_class_name, query_obj.component_names):
				__bind_to_systems(entity, query_name, query_obj.subscribers)


func _entity_component_removed(component: Node, entity: Node, bound_queries: Array) -> void:
	if _scene_changing:
		return;
	var index := 0
	var query_name: String
	var component_name := component.name
	entity.remove_meta("$" + component_name)
	while index < bound_queries.size():
		query_name = bound_queries[index]
		if not component_name in query_name:
			index += 1
			continue
		__remove_query_from_entity(entity, query_name)
		bound_queries.remove(index)


func _init() -> void:
	add_to_group("#q-godot")


func _ready() -> void:
	_root = get_tree().root
	yield(_root, "ready")
	_scene_changing = false
	__post_change_scene(get_tree().current_scene)


func _process(_delta: float) -> void:
	switch = not switch
