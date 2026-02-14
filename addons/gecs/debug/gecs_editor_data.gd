@tool
class_name GECSEditorData
extends RefCounted

## Signals for ECS events
signal world_init(world_id: int, world_path: NodePath)
signal set_world(world_id: int, world_path: NodePath)
signal process_world(delta: float, group_name: String)
signal exit_world()

signal entity_added(entity_id: int, path: NodePath)
signal entity_removed(entity_id: int, path: NodePath)
signal entity_disabled(entity_id: int, path: NodePath)
signal entity_enabled(entity_id: int, path: NodePath)

signal system_added(sys_id: int, group: String, process_empty: bool, active: bool, paused: bool, path: NodePath)
signal system_removed(sys_id: int, path: NodePath)
signal system_metric(sys_id: int, system_name: String, time: float)
signal system_last_run_data(sys_id: int, system_name: String, last_run_data: Dictionary)
signal system_active_changed(sys_id: int, active: bool)

signal component_added(entity_id: int, component_id: int, component_path: String, data: Dictionary)
signal component_removed(entity_id: int, component_id: int)
signal component_property_changed(entity_id: int, component_id: int, property_name: String, old_value: Variant, new_value: Variant)

signal relationship_added(entity_id: int, relationship_id: int, relationship_data: Dictionary)
signal relationship_removed(entity_id: int, relationship_id: int)


## Data Storage
var ecs_data: Dictionary = {}

## Defaults
const DEFAULT_SYSTEM := {"path": "", "active": true, "metrics": {}, "group": ""}
const DEFAULT_ENTITY := {"path": "", "active": true, "components": {}, "relationships": {}}

## Helper to ensure dictionary keys exist
func get_or_create_dict(dict: Dictionary, key, default_val = {}) -> Dictionary:
	if not dict.has(key):
		dict[key] = default_val
	return dict[key]


## Clears all data (e.g. on session start)
func clear() -> void:
	ecs_data.clear()


## Message Handlers

func on_world_init(world_id: int, world_path: NodePath) -> void:
	var world_dict := get_or_create_dict(ecs_data, "world")
	world_dict["id"] = world_id
	world_dict["path"] = world_path
	world_init.emit(world_id, world_path)


func on_set_world(world_id: int, world_path: NodePath) -> void:
	var world_dict := get_or_create_dict(ecs_data, "world")
	world_dict["id"] = world_id
	world_dict["path"] = world_path
	set_world.emit(world_id, world_path)


func on_process_world(delta: float, group_name: String) -> void:
	var world_dict := get_or_create_dict(ecs_data, "world")
	world_dict["delta"] = delta
	world_dict["active_group"] = group_name
	process_world.emit(delta, group_name)


func on_exit_world() -> void:
	ecs_data["exited"] = true
	exit_world.emit()


func on_entity_added(entity_id: int, path: NodePath) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	# Merge with existing (possibly placeholder) data
	var existing := entities.get(entity_id, {})
	var existing_components: Dictionary = existing.get("components", {})
	var existing_relationships: Dictionary = existing.get("relationships", {})

	entities[entity_id] = {
		"path": path,
		"active": true,
		"components": existing_components,
		"relationships": existing_relationships
	}
	entity_added.emit(entity_id, path)


func on_entity_removed(entity_id: int, path: NodePath) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	entities.erase(entity_id)
	entity_removed.emit(entity_id, path)


func on_entity_disabled(entity_id: int, path: NodePath) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	if entities.has(entity_id):
		entities[entity_id]["active"] = false
	entity_disabled.emit(entity_id, path)


func on_entity_enabled(entity_id: int, path: NodePath) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	if entities.has(entity_id):
		entities[entity_id]["active"] = true
	entity_enabled.emit(entity_id, path)


func on_system_added(sys_id: int, group: String, process_empty: bool, active: bool, paused: bool, path: NodePath) -> void:
	var systems_data := get_or_create_dict(ecs_data, "systems")
	systems_data[sys_id] = DEFAULT_SYSTEM.duplicate()
	systems_data[sys_id]["path"] = path
	systems_data[sys_id]["group"] = group
	systems_data[sys_id]["process_empty"] = process_empty
	systems_data[sys_id]["active"] = active
	systems_data[sys_id]["paused"] = paused
	system_added.emit(sys_id, group, process_empty, active, paused, path)


func on_system_removed(sys_id: int, path: NodePath) -> void:
	var systems_data := get_or_create_dict(ecs_data, "systems")
	systems_data.erase(sys_id)
	system_removed.emit(sys_id, path)


func on_system_metric(sys_id: int, system_name: String, time: float) -> void:
	var systems_data := get_or_create_dict(ecs_data, "systems")
	var sys_entry := get_or_create_dict(systems_data, sys_id, DEFAULT_SYSTEM.duplicate())

	sys_entry["last_time"] = time
	var sys_metrics = sys_entry.get("metrics")
	if not sys_metrics:
		sys_metrics = {"min_time": time, "max_time": time, "avg_time": time, "count": 1, "last_time": time}
	else:
		sys_metrics["min_time"] = min(sys_metrics["min_time"], time)
		sys_metrics["max_time"] = max(sys_metrics["max_time"], time)
		sys_metrics["count"] += 1
		sys_metrics["avg_time"] = (
			((sys_metrics["avg_time"] * (sys_metrics["count"] - 1)) + time) / sys_metrics["count"]
		)
		sys_metrics["last_time"] = time

	sys_entry["metrics"] = sys_metrics
	system_metric.emit(sys_id, system_name, time)


func on_system_last_run_data(sys_id: int, system_name: String, last_run_data: Dictionary) -> void:
	var systems_data := get_or_create_dict(ecs_data, "systems")
	var sys_entry := get_or_create_dict(systems_data, sys_id, DEFAULT_SYSTEM.duplicate())
	sys_entry["last_run_data"] = last_run_data
	system_last_run_data.emit(sys_id, system_name, last_run_data)


func on_component_added(entity_id: int, component_id: int, component_path: String, data: Dictionary) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	var entity := get_or_create_dict(entities, entity_id)
	if not entity.has("components"):
		entity["components"] = {}

	# Fallback logic for empty data (same as original debugger tab)
	var final_data = data
	if final_data.is_empty():
		final_data = {}
		final_data["<no_serialized_properties>"] = true

	# Store wrapped component data to preserve path/type info
	entity["components"][component_id] = {
		"data": final_data,
		"path": component_path
	}
	component_added.emit(entity_id, component_id, component_path, final_data)


func on_component_removed(entity_id: int, component_id: int) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	if entities.has(entity_id) and entities[entity_id].has("components"):
		entities[entity_id]["components"].erase(component_id)
	component_removed.emit(entity_id, component_id)


func on_component_property_changed(entity_id: int, component_id: int, property_name: String, old_value: Variant, new_value: Variant) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	if entities.has(entity_id) and entities[entity_id].has("components"):
		var component_entry = entities[entity_id]["components"].get(component_id)
		if component_entry and component_entry.has("data"):
			component_entry["data"][property_name] = new_value
	component_property_changed.emit(entity_id, component_id, property_name, old_value, new_value)


func on_relationship_added(entity_id: int, relationship_id: int, relationship_data: Dictionary) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	var entity := get_or_create_dict(entities, entity_id)
	var relationships := get_or_create_dict(entity, "relationships")
	relationships[relationship_id] = relationship_data
	relationship_added.emit(entity_id, relationship_id, relationship_data)


func on_relationship_removed(entity_id: int, relationship_id: int) -> void:
	var entities := get_or_create_dict(ecs_data, "entities")
	if entities.has(entity_id) and entities[entity_id].has("relationships"):
		entities[entity_id]["relationships"].erase(relationship_id)
	relationship_removed.emit(entity_id, relationship_id)
