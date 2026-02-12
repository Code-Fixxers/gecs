@tool
class_name EntitySyncMetadata
extends Resource
## Per-entity sync configuration stored as .sync.tres alongside entity scripts.
##
## Provides a visual overview of entity network configuration.
## Used by the Sync Dashboard to display and edit entity sync patterns.
##
## Usage:
##   # Stored at: game/entities/e_enemy.sync.tres
##   # Describes: game/entities/e_enemy.gd

enum SyncPattern {
	NONE,        ## No network sync (local-only entity)
	SPAWN_ONLY,  ## Server broadcasts spawn data once, clients simulate locally
	CONTINUOUS   ## Real-time sync via MultiplayerSynchronizer
}

enum Ownership {
	SERVER,  ## Server-owned (peer_id=0): enemies, projectiles, pickups
	PLAYER   ## Player-owned (peer_id>0): player entities
}

## Path to the entity script this metadata applies to.
## Example: "res://game/entities/e_enemy.gd"
@export var entity_script_path: String = ""

## Network sync pattern for this entity type.
@export var sync_pattern: SyncPattern = SyncPattern.SPAWN_ONLY

## Entity ownership model.
@export var ownership: Ownership = Ownership.SERVER

## Whether to sync global_position via native MultiplayerSynchronizer.
@export var sync_position: bool = true

## Whether to sync global_rotation via native MultiplayerSynchronizer.
@export var sync_rotation: bool = false

## Whether to sync velocity via native MultiplayerSynchronizer.
@export var sync_velocity: bool = false

## Custom properties to sync via native MultiplayerSynchronizer.
## Example: ["Rig:rotation"]
@export var custom_properties: Array[String] = []
