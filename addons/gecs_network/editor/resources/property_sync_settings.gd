@tool
class_name PropertySyncSettings
extends Resource
## Per-property sync configuration stored in .sync.tres metadata files.
##
## Used by ComponentSyncMetadata to override @export_group() annotations
## without modifying the component script.

## Whether this property should be synced over the network.
## When false, the property is treated as LOCAL regardless of priority.
@export var sync_enabled: bool = true

## Sync priority for this property.
## Maps to SyncConfig.Priority enum values (0=REALTIME, 1=HIGH, 2=MEDIUM, 3=LOW).
## Use -1 for LOCAL (never synced).
@export var priority: int = 1  # Default: HIGH
