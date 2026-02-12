class_name SyncMetadataRegistry
extends RefCounted
## Runtime registry for .sync.tres metadata files.
##
## Loaded at runtime (not just editor). SyncComponent._parse_property_priorities()
## checks this registry first. If a .sync.tres file exists for the component,
## its priority settings override the @export_group() annotations in code.
##
## Usage:
##   var metadata = SyncMetadataRegistry.get_component_metadata("res://game/components/combat/c_health.gd")
##   if metadata:
##       # Use metadata priorities instead of code annotations

## Cache of loaded metadata: {script_path: ComponentSyncMetadata}
static var _component_cache: Dictionary = {}

## Cache of entity metadata: {script_path: EntitySyncMetadata}
static var _entity_cache: Dictionary = {}


## Get component sync metadata for a script path.
## Returns null if no .sync.tres file exists.
static func get_component_metadata(script_path: String) -> ComponentSyncMetadata:
	if _component_cache.has(script_path):
		return _component_cache[script_path]

	var tres_path := script_path.replace(".gd", ".sync.tres")
	if ResourceLoader.exists(tres_path):
		var res := load(tres_path)
		if res is ComponentSyncMetadata:
			_component_cache[script_path] = res
			return res

	# Cache null result to avoid repeated file checks
	_component_cache[script_path] = null
	return null


## Get entity sync metadata for a script path.
## Returns null if no .sync.tres file exists.
static func get_entity_metadata(script_path: String) -> EntitySyncMetadata:
	if _entity_cache.has(script_path):
		return _entity_cache[script_path]

	var tres_path := script_path.replace(".gd", ".sync.tres")
	if ResourceLoader.exists(tres_path):
		var res := load(tres_path)
		if res is EntitySyncMetadata:
			_entity_cache[script_path] = res
			return res

	# Cache null result to avoid repeated file checks
	_entity_cache[script_path] = null
	return null


## Clear all caches. Call when .sync.tres files are created/modified.
static func clear_cache() -> void:
	_component_cache.clear()
	_entity_cache.clear()


## Clear cache for a specific component script path.
static func invalidate_component(script_path: String) -> void:
	_component_cache.erase(script_path)


## Clear cache for a specific entity script path.
static func invalidate_entity(script_path: String) -> void:
	_entity_cache.erase(script_path)
