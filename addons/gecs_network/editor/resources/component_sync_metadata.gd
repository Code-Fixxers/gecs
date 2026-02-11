@tool
class_name ComponentSyncMetadata
extends Resource
## Per-component sync configuration stored as .sync.tres alongside component scripts.
##
## Provides visual/non-destructive override for @export_group() annotations.
## When present, SyncComponent._parse_property_priorities() uses these settings
## instead of parsing @export_group annotations from the script.
##
## Usage:
##   # Automatically loaded by SyncMetadataRegistry
##   # Stored at: game/components/combat/c_health.sync.tres
##   # Overrides: game/components/combat/c_health.gd

## Path to the component script this metadata applies to.
## Example: "res://game/components/combat/c_health.gd"
@export var component_script_path: String = ""

## Whether this component should be synced at all.
## When false, the entire component is treated as local-only.
@export var sync_enabled: bool = true

## Default priority for properties without explicit settings.
## Maps to SyncConfig.Priority enum: 0=REALTIME, 1=HIGH, 2=MEDIUM, 3=LOW
@export var default_priority: int = 1  # Default: HIGH

## Per-property sync settings.
## Key: property name (String), Value: PropertySyncSettings resource.
## Only properties listed here override the code defaults.
## Properties not in this dictionary use the @export_group() annotation from code.
@export var properties: Dictionary = {}


## Get the priority map in the format SyncComponent expects.
## Returns: {priority_int: [prop_names]}
func get_priority_map() -> Dictionary:
	var result: Dictionary = {}

	for prop_name in properties.keys():
		var settings = properties[prop_name] as PropertySyncSettings
		if settings == null:
			continue

		var priority: int
		if not settings.sync_enabled:
			priority = -1  # LOCAL
		else:
			priority = settings.priority

		if priority not in result:
			result[priority] = []
		result[priority].append(prop_name)

	return result
