@tool
extends RefCounted
## Scans the project for Component, SyncComponent, and Entity scripts.
##
## Finds all relevant GDScript files, parses their properties and inheritance,
## and returns structured data for the Sync Dashboard to display.

## Result of scanning a component script
class ComponentInfo:
	var script_path: String
	var class_name_str: String
	var is_sync_component: bool
	## {property_name: {priority: int, type: String}}
	var properties: Dictionary
	var metadata: ComponentSyncMetadata  # null if no .sync.tres

	func _init(p_path: String = "", p_name: String = "", p_is_sync: bool = false) -> void:
		script_path = p_path
		class_name_str = p_name
		is_sync_component = p_is_sync
		properties = {}
		metadata = null

## Result of scanning an entity script
class EntityInfo:
	var script_path: String
	var class_name_str: String
	## Array of component class names used in define_components()
	var component_names: Array[String]
	var has_sync_entity: bool
	var has_network_identity: bool
	var sync_position: bool
	var sync_rotation: bool
	var sync_velocity: bool
	var custom_properties: Array[String]
	var peer_id_value: int  # -1 if unknown, 0=server, >0=player
	var metadata: EntitySyncMetadata  # null if no .sync.tres

	func _init(p_path: String = "", p_name: String = "") -> void:
		script_path = p_path
		class_name_str = p_name
		component_names = []
		has_sync_entity = false
		has_network_identity = false
		sync_position = false
		sync_rotation = false
		sync_velocity = false
		custom_properties = []
		peer_id_value = -1
		metadata = null

## Cached scan results
var components: Array = []  # Array of ComponentInfo
var entities: Array = []  # Array of EntityInfo

## Directories to scan (configurable).
## Defaults to scanning the entire project, excluding addons and hidden directories.
var scan_directories: Array[String] = ["res://"]

## Directories to skip during scanning.
var skip_directories: Array[String] = ["res://addons/", "res://.godot/"]

## Pre-compiled regex patterns (avoid recompiling per call)
var _component_ref_regex: RegEx
var _sync_entity_config_regex: RegEx
var _custom_property_regex: RegEx
var _network_identity_regex: RegEx


func _init() -> void:
	_component_ref_regex = RegEx.new()
	_component_ref_regex.compile("\\b(C[N]?_[A-Za-z0-9]+)\\b")

	_sync_entity_config_regex = RegEx.new()
	_sync_entity_config_regex.compile("CN_SyncEntity\\.new\\(\\s*(true|false)\\s*,\\s*(true|false)\\s*,\\s*(true|false)\\s*\\)")

	_custom_property_regex = RegEx.new()
	_custom_property_regex.compile("custom_properties\\.append\\(\"([^\"]+)\"\\)")

	_network_identity_regex = RegEx.new()
	_network_identity_regex.compile("CN_NetworkIdentity\\.new\\(\\s*(\\d+)\\s*\\)")


## Scan the project for all components and entities.
## Call this when the Scan button is pressed.
func scan() -> void:
	components.clear()
	entities.clear()

	var script_paths := _find_gd_files(scan_directories)

	for path in script_paths:
		var script := load(path) as GDScript
		if script == null:
			continue

		var global_name := script.get_global_name()
		if global_name == "":
			global_name = path.get_file().get_basename()

		if _is_entity_subclass(script):
			var info := _scan_entity(path, global_name, script)
			entities.append(info)
		elif _is_sync_component_subclass(script):
			var info := _scan_sync_component(path, global_name, script)
			components.append(info)
		elif _is_component_subclass(script):
			var info := ComponentInfo.new(path, global_name, false)
			_load_component_metadata(info)
			components.append(info)

	# Sort by class name
	components.sort_custom(func(a, b): return a.class_name_str.naturalcasecmp_to(b.class_name_str) < 0)
	entities.sort_custom(func(a, b): return a.class_name_str.naturalcasecmp_to(b.class_name_str) < 0)


## Find all .gd files in the given directories recursively.
func _find_gd_files(directories: Array[String]) -> Array[String]:
	var results: Array[String] = []
	for dir_path in directories:
		_scan_directory_recursive(dir_path, results)
	return results


func _scan_directory_recursive(path: String, results: Array[String]) -> void:
	# Skip excluded directories
	for skip_dir in skip_directories:
		if path.begins_with(skip_dir):
			return

	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory_recursive(full_path, results)
		elif file_name.ends_with(".gd"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Check if a script inherits from Entity (directly or transitively).
func _is_entity_subclass(script: GDScript) -> bool:
	var s := script
	while s != null:
		if s.get_global_name() == "Entity":
			return true
		s = s.get_base_script()
	return false


## Check if a script inherits from SyncComponent.
func _is_sync_component_subclass(script: GDScript) -> bool:
	var s := script
	while s != null:
		if s.get_global_name() == "SyncComponent":
			return true
		s = s.get_base_script()
	return false


## Check if a script inherits from Component (but not SyncComponent).
func _is_component_subclass(script: GDScript) -> bool:
	var s := script
	while s != null:
		var name := s.get_global_name()
		if name == "SyncComponent":
			return false  # It's a SyncComponent, not just Component
		if name == "Component":
			return true
		s = s.get_base_script()
	return false


## Scan a SyncComponent subclass for its exported properties and priorities.
func _scan_sync_component(path: String, class_name_str: String, script: GDScript) -> ComponentInfo:
	var info := ComponentInfo.new(path, class_name_str, true)

	# Parse properties using the same approach as SyncComponent._parse_property_priorities()
	var current_group := "HIGH"  # Default priority

	for prop_info in script.get_script_property_list():
		var usage: int = prop_info.usage

		# Detect @export_group annotations
		if usage & PROPERTY_USAGE_GROUP:
			var group_name: String = prop_info.name
			if group_name in ["REALTIME", "HIGH", "MEDIUM", "LOW", "LOCAL"]:
				current_group = group_name
			continue

		# Detect exported properties
		if usage & PROPERTY_USAGE_EDITOR and not (usage & PROPERTY_USAGE_CATEGORY):
			var prop_name: String = prop_info.name
			var priority := _group_to_priority(current_group)
			info.properties[prop_name] = {
				"priority": priority,
				"type": type_string(prop_info.type),
				"group": current_group
			}

	_load_component_metadata(info)
	return info


## Scan an Entity subclass for its define_components() configuration.
func _scan_entity(path: String, class_name_str: String, script: GDScript) -> EntityInfo:
	var info := EntityInfo.new(path, class_name_str)

	# Parse the source code to extract define_components() information
	var source := script.source_code
	if source == "":
		_load_entity_metadata(info)
		return info

	# Find component class names referenced in define_components()
	var in_define := false
	var lines := source.split("\n")

	for line in lines:
		var stripped := line.strip_edges()

		if stripped.begins_with("func define_components"):
			in_define = true
			continue

		if in_define:
			# Track return array scope
			if stripped.begins_with("func ") and not stripped.begins_with("func define_components"):
				break

			# Look for component references: C_ClassName.new(), C_ClassName (variable)
			_extract_component_refs(stripped, info)

	# Check for CN_SyncEntity and CN_NetworkIdentity based on parsed component refs
	info.has_sync_entity = "CN_SyncEntity" in info.component_names
	info.has_network_identity = "CN_NetworkIdentity" in info.component_names

	# Parse CN_SyncEntity configuration from source
	_parse_sync_entity_config(source, info)

	# Parse CN_NetworkIdentity peer_id
	_parse_network_identity(source, info)

	_load_entity_metadata(info)
	return info


## Extract component class name references from a line of source code.
func _extract_component_refs(line: String, info: EntityInfo) -> void:
	# Match patterns like: C_Health.new(), CN_SyncEntity.new(), C_Collider.enemy_detection()
	var matches := _component_ref_regex.search_all(line)
	for m in matches:
		var comp_name := m.get_string(1)
		if comp_name not in info.component_names:
			info.component_names.append(comp_name)


## Parse CN_SyncEntity constructor arguments from source code.
func _parse_sync_entity_config(source: String, info: EntityInfo) -> void:
	# Look for CN_SyncEntity.new(true, false, false) pattern
	var m := _sync_entity_config_regex.search(source)
	if m:
		info.sync_position = m.get_string(1) == "true"
		info.sync_rotation = m.get_string(2) == "true"
		info.sync_velocity = m.get_string(3) == "true"

	# Look for custom_properties.append("...") patterns
	var custom_matches := _custom_property_regex.search_all(source)
	for cm in custom_matches:
		var prop := cm.get_string(1)
		if prop not in info.custom_properties:
			info.custom_properties.append(prop)


## Parse CN_NetworkIdentity peer_id from source code.
func _parse_network_identity(source: String, info: EntityInfo) -> void:
	var m := _network_identity_regex.search(source)
	if m:
		info.peer_id_value = m.get_string(1).to_int()


## Load .sync.tres metadata for a component if it exists.
func _load_component_metadata(info: ComponentInfo) -> void:
	var tres_path := info.script_path.replace(".gd", ".sync.tres")
	if ResourceLoader.exists(tres_path):
		var res := load(tres_path)
		if res is ComponentSyncMetadata:
			info.metadata = res


## Load .sync.tres metadata for an entity if it exists.
func _load_entity_metadata(info: EntityInfo) -> void:
	var tres_path := info.script_path.replace(".gd", ".sync.tres")
	if ResourceLoader.exists(tres_path):
		var res := load(tres_path)
		if res is EntitySyncMetadata:
			info.metadata = res


## Convert priority group string to integer.
static func _group_to_priority(group: String) -> int:
	match group:
		"REALTIME": return 0  # SyncConfig.Priority.REALTIME
		"HIGH": return 1      # SyncConfig.Priority.HIGH
		"MEDIUM": return 2    # SyncConfig.Priority.MEDIUM
		"LOW": return 3       # SyncConfig.Priority.LOW
		"LOCAL": return -1
		_: return 1  # Default: HIGH


## Convert priority integer to display string.
static func priority_to_string(priority: int) -> String:
	match priority:
		0: return "REALTIME"
		1: return "HIGH"
		2: return "MEDIUM"
		3: return "LOW"
		-1: return "LOCAL"
		_: return "HIGH"


## Convert priority integer to sync rate display string.
static func priority_to_rate(priority: int) -> String:
	match priority:
		0: return "~60 Hz"
		1: return "20 Hz"
		2: return "10 Hz"
		3: return "1 Hz"
		-1: return "--"
		_: return "20 Hz"
