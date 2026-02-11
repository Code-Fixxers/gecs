@tool
extends RefCounted
## Generates code snippets from dashboard configuration for copy-paste.
##
## Produces project_sync_config.gd component_priorities dictionary
## and entity define_components() network configuration snippets.


## Generate component_priorities dictionary code from scanned components.
## Returns a string suitable for pasting into project_sync_config.gd _init().
static func generate_component_priorities(components: Array, config_priorities: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("\tcomponent_priorities = {")

	# Group components by priority for organized output
	var by_priority: Dictionary = {}  # {priority_int: [{name, comment}]}

	for comp in components:
		if not comp.is_sync_component:
			continue

		var class_name_str: String = comp.class_name_str
		var priority: int = config_priorities.get(class_name_str, -99)

		# If component has metadata override, use that
		if comp.metadata and comp.metadata is ComponentSyncMetadata:
			priority = comp.metadata.default_priority

		if priority == -99:
			continue  # Not in config, skip

		if priority not in by_priority:
			by_priority[priority] = []
		by_priority[priority].append(class_name_str)

	# Output grouped by priority
	var priority_names := {0: "REALTIME", 1: "HIGH", 2: "MEDIUM", 3: "LOW"}
	var priority_comments := {
		0: "REALTIME (~60 Hz) - Every frame",
		1: "HIGH (20 Hz) - Fast-changing data",
		2: "MEDIUM (10 Hz) - Important but less frequent",
		3: "LOW (1 Hz) - Rarely changing data"
	}

	for priority in [0, 1, 2, 3]:
		if priority not in by_priority:
			continue

		var names: Array = by_priority[priority]
		names.sort()

		lines.append("\t\t# %s" % priority_comments[priority])
		for comp_name in names:
			lines.append('\t\t"%s": Priority.%s,' % [comp_name, priority_names[priority]])

	lines.append("\t}")
	return "\n".join(lines)


## Generate CN_SyncEntity configuration snippet for an entity.
static func generate_sync_entity_snippet(entity_info) -> String:
	if not entity_info.has_sync_entity:
		return "# No CN_SyncEntity configured"

	var lines: PackedStringArray = []

	var args := "(%s, %s, %s)" % [
		str(entity_info.sync_position).to_lower(),
		str(entity_info.sync_rotation).to_lower(),
		str(entity_info.sync_velocity).to_lower()
	]
	lines.append("var sync = CN_SyncEntity.new%s" % args)

	for prop in entity_info.custom_properties:
		lines.append('sync.custom_properties.append("%s")' % prop)

	return "\n".join(lines)


## Generate CN_NetworkIdentity snippet for an entity.
static func generate_network_identity_snippet(entity_info) -> String:
	if not entity_info.has_network_identity:
		return "# No CN_NetworkIdentity configured"

	if entity_info.peer_id_value >= 0:
		return "CN_NetworkIdentity.new(%d)  # %s" % [
			entity_info.peer_id_value,
			"server-owned" if entity_info.peer_id_value == 0 else "player-owned (peer_id=%d)" % entity_info.peer_id_value
		]

	return "CN_NetworkIdentity.new(peer_id)"


## Generate a full entity network config preview combining identity + sync.
static func generate_entity_network_preview(entity_info) -> String:
	var lines: PackedStringArray = []
	lines.append("# Network configuration for %s" % entity_info.class_name_str)
	lines.append("")
	lines.append(generate_network_identity_snippet(entity_info))
	lines.append("")
	lines.append(generate_sync_entity_snippet(entity_info))
	return "\n".join(lines)


## Generate skip_component_types array code.
static func generate_skip_list(skip_types: Array[String]) -> String:
	if skip_types.is_empty():
		return '\tskip_component_types = []'

	var items: PackedStringArray = []
	for t in skip_types:
		items.append('"%s"' % t)
	return '\tskip_component_types = [%s]' % ", ".join(items)
