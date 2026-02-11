class_name SyncComponent
extends Component
## SyncComponent - Automatically syncs @export properties at configurable intervals.
##
## Use @export_group to specify sync priority per property:
##   @export_group("HIGH")      # 20 Hz - position, velocity
##   @export var position: Vector3
##
##   @export_group("MEDIUM")    # 10 Hz - health, state
##   @export var health: int
##
##   @export_group("LOW")       # 1 Hz - XP, inventory
##   @export var xp: int
##
##   @export_group("LOCAL")     # Not synced
##   @export var is_invincible: bool
##
## Properties without a group default to HIGH priority.
## NetworkSync polls check_changes_for_priority() at each priority's interval.


# Priority string to SyncConfig.Priority enum mapping
const PRIORITY_MAP = {
	"REALTIME": SyncConfig.Priority.REALTIME,
	"HIGH": SyncConfig.Priority.HIGH,
	"MEDIUM": SyncConfig.Priority.MEDIUM,
	"LOW": SyncConfig.Priority.LOW,
	"LOCAL": -1     # Special: never synced
}

## Cache of last-known values: {prop_name: value}
var _sync_cache: Dictionary = {}

## Properties grouped by priority: {priority_int: [prop_names]}
var _props_by_priority: Dictionary = {}

## Initialization complete flag
var _sync_initialized: bool = false


## Initialize the sync cache and property groupings (called lazily on first use)
func _ensure_initialized() -> void:
	if _sync_initialized:
		return

	_props_by_priority = _parse_property_priorities()

	# Initialize cache for all synced properties (skip LOCAL)
	for priority in _props_by_priority.keys():
		if priority == -1:  # LOCAL priority
			continue
		for prop_name in _props_by_priority[priority]:
			_sync_cache[prop_name] = _deep_copy(get(prop_name))

	_sync_initialized = true


## Parse @export properties and group them by @export_group priority.
## Checks for .sync.tres metadata override first (from Sync Dashboard editor tool).
## Falls back to @export_group() annotation parsing if no metadata exists.
## Returns: {priority_int: [prop_names]}
func _parse_property_priorities() -> Dictionary:
	# Check for .sync.tres metadata override (set via Sync Dashboard)
	var metadata := _get_sync_metadata()
	if metadata:
		return _parse_from_metadata(metadata)

	# Fall back to @export_group() annotation parsing
	return _parse_from_annotations()


## Try to load .sync.tres metadata for this component via SyncMetadataRegistry.
func _get_sync_metadata():  # -> ComponentSyncMetadata or null
	var script := get_script()
	if script == null:
		return null
	var script_path: String = script.resource_path
	if script_path == "":
		return null

	# SyncMetadataRegistry is a GDScript class with static methods.
	# Load it directly since GDScript class_name globals aren't always resolvable
	# from a base class context (SyncComponent doesn't know about editor classes).
	var registry_path := "res://addons/gecs_network/editor/sync_metadata_registry.gd"
	if not ResourceLoader.exists(registry_path):
		return null
	var registry_script := load(registry_path) as GDScript
	if registry_script == null:
		return null
	return registry_script.get_component_metadata(script_path)


## Parse priorities from .sync.tres metadata.
## Only overrides properties that are explicitly listed in the metadata.
## Properties not in metadata fall through to annotation parsing.
func _parse_from_metadata(metadata) -> Dictionary:
	if not metadata.has_method("get_priority_map"):
		return _parse_from_annotations()
	var metadata_map: Dictionary = metadata.get_priority_map()

	# If metadata covers all properties, use it directly
	if not metadata_map.is_empty():
		# Get annotation-based result as baseline
		var annotation_result := _parse_from_annotations()

		# Override with metadata values
		var metadata_props := {}
		for priority in metadata_map.keys():
			for prop_name in metadata_map[priority]:
				metadata_props[prop_name] = true

		# Remove overridden properties from annotation result
		for priority in annotation_result.keys():
			var filtered: Array = []
			for prop_name in annotation_result[priority]:
				if prop_name not in metadata_props:
					filtered.append(prop_name)
			if filtered.is_empty():
				annotation_result.erase(priority)
			else:
				annotation_result[priority] = filtered

		# Merge metadata priorities into result
		for priority in metadata_map.keys():
			if priority not in annotation_result:
				annotation_result[priority] = []
			annotation_result[priority].append_array(metadata_map[priority])

		return annotation_result

	# Empty metadata properties = use annotations entirely
	return _parse_from_annotations()


## Original annotation-based parsing: reads @export_group() from script property list.
func _parse_from_annotations() -> Dictionary:
	var result: Dictionary = {}
	var current_group: String = "HIGH"  # Default priority

	for prop_info in get_script().get_script_property_list():
		var usage = prop_info.usage

		# Check if this is an @export_group annotation
		if usage & PROPERTY_USAGE_GROUP:
			var group_name = prop_info.name
			# Extract priority from group name (e.g., "HIGH", "MEDIUM", "LOW", "LOCAL")
			if group_name in PRIORITY_MAP:
				current_group = group_name
			continue

		# Check if this is an exported property
		if usage & PROPERTY_USAGE_EDITOR and not (usage & PROPERTY_USAGE_CATEGORY):
			var prop_name: String = prop_info.name

			# Map current group to priority enum value
			var priority = PRIORITY_MAP.get(current_group, 1)  # Default to HIGH

			# Add property to this priority's list
			if priority not in result:
				result[priority] = []
			result[priority].append(prop_name)

	return result


## Check for changes in properties of a specific priority level.
## Called by NetworkSync at each priority's sync interval.
## Returns: Dictionary of changed properties {prop_name: new_value}
func check_changes_for_priority(priority: int) -> Dictionary:
	_ensure_initialized()

	var changed_props: Dictionary = {}
	var props_to_check = _props_by_priority.get(priority, [])

	for prop_name in props_to_check:
		var current_value = get(prop_name)
		var cached_value = _sync_cache.get(prop_name)

		if _has_changed(cached_value, current_value):
			changed_props[prop_name] = current_value
			var old_value = cached_value
			_sync_cache[prop_name] = _deep_copy(current_value)
			property_changed.emit(self, prop_name, old_value, current_value)

	return changed_props


## Get the sync priority for a specific property.
## Returns: SyncConfig.Priority enum value, or -1 for LOCAL
func get_priority_for_property(prop_name: String) -> int:
	_ensure_initialized()
	for priority in _props_by_priority.keys():
		if prop_name in _props_by_priority[priority]:
			return priority
	return 1  # Default to HIGH if not found


## Update cache without emitting property_changed signal.
## Used when applying network data to avoid sync loops.
func update_cache_silent(prop_name: String, value: Variant) -> void:
	_sync_cache[prop_name] = _deep_copy(value)


## Check if two values are different, using appropriate comparison method.
## Auto-detects type: approximate comparison for vectors/floats, exact for others.
# gdlint: disable=max-returns
func _has_changed(old_value: Variant, new_value: Variant) -> bool:
	# Null checks
	if old_value == null and new_value == null:
		return false
	if old_value == null or new_value == null:
		return true

	# Type-specific comparisons
	var old_type = typeof(old_value)
	var new_type = typeof(new_value)

	if old_type != new_type:
		return true

	# Approximate comparison for floating-point types
	match old_type:
		TYPE_FLOAT:
			return not is_equal_approx(old_value, new_value)
		TYPE_VECTOR2:
			return not old_value.is_equal_approx(new_value)
		TYPE_VECTOR3:
			return not old_value.is_equal_approx(new_value)
		TYPE_VECTOR4:
			return not old_value.is_equal_approx(new_value)
		TYPE_TRANSFORM2D:
			return not (
				old_value.origin.is_equal_approx(new_value.origin) and
				old_value.x.is_equal_approx(new_value.x) and
				old_value.y.is_equal_approx(new_value.y)
			)
		TYPE_TRANSFORM3D:
			return not (
				old_value.origin.is_equal_approx(new_value.origin) and
				old_value.basis.x.is_equal_approx(new_value.basis.x) and
				old_value.basis.y.is_equal_approx(new_value.basis.y) and
				old_value.basis.z.is_equal_approx(new_value.basis.z)
			)
		TYPE_QUATERNION:
			return not old_value.is_equal_approx(new_value)
		TYPE_COLOR:
			return not old_value.is_equal_approx(new_value)

	# Exact comparison for all other types (int, bool, String, etc.)
	return old_value != new_value


## Deep copy a value to avoid reference issues with objects/arrays.
func _deep_copy(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			return value  # Vectors are value types in Godot, no copy needed
		TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_QUATERNION:
			return value  # Transforms are value types
		TYPE_ARRAY:
			return value.duplicate(true)
		TYPE_DICTIONARY:
			return value.duplicate(true)
		_:
			return value  # Primitives (int, float, bool, String) are value types
