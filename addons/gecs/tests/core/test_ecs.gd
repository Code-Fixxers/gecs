# addons/gecs/tests/core/test_ecs.gd
extends GdUnitTestSuite

const C_Position = preload("res://addons/gecs/tests/components/c_position.gd")
const C_Velocity = preload("res://addons/gecs/tests/components/c_velocity.gd")

var runner: GdUnitSceneRunner
var world: World

func before():
	runner = scene_runner("res://addons/gecs/tests/test_scene.tscn")
	world = runner.get_property("world")
	# Ensure ECS.world is null before each test if it wasn't already
	ECS.world = null

func after_test():
	if ECS.world:
		ECS.world = null
	if world:
		world.purge(false)

func test_world_property() -> void:
	assert_object(ECS.world).is_null()
	ECS.world = world
	assert_object(ECS.world).is_equal(world)
	ECS.world = null
	assert_object(ECS.world).is_null()

func test_world_changed_signal() -> void:
	var monitor := monitor_signals(ECS)
	ECS.world = world
	# Signal is emitted synchronously in the setter
	verify_signal(monitor).is_emitted("world_changed", [world])

func test_world_exited_signal() -> void:
	ECS.world = world
	var monitor := monitor_signals(ECS)
	# Simulate world exiting
	ECS._on_world_exited()
	verify_signal(monitor).is_emitted("world_exited")
	assert_object(ECS.world).is_null()

func test_process() -> void:
	ECS.world = world
	# ECS.process just delegates to world.process
	ECS.process(0.1)
	ECS.process(0.1, "physics")

func test_get_components() -> void:
	var e1 = Entity.new()
	var p1 = C_Position.new()
	e1.add_component(p1)

	var e2 = Entity.new()
	var p2 = C_Position.new()
	e2.add_component(p2)

	var entities = [e1, e2]
	var components = ECS.get_components(entities, C_Position)

	assert_array(components).is_equal([p1, p2])

	e1.free()
	e2.free()

func test_get_components_with_default() -> void:
	var e1 = Entity.new()
	var p1 = C_Position.new()
	e1.add_component(p1)

	var e2 = Entity.new() # No position

	var default_p = C_Position.new()
	var entities = [e1, e2]
	var components = ECS.get_components(entities, C_Position, default_p)

	assert_array(components).is_equal([p1, default_p])

	e1.free()
	e2.free()

func test_entity_preprocessors() -> void:
	var called_count := 0
	var preprocessor := func(entity: Entity):
		called_count += 1

	ECS.entity_preprocessors.append(preprocessor)

	var test_world = World.new()
	var old_world = ECS.world
	ECS.world = test_world

	var entity = Entity.new()
	test_world.add_entity(entity)

	assert_int(called_count).is_equal(1)

	# Clean up
	ECS.entity_preprocessors.erase(preprocessor)
	ECS.world = old_world
	test_world.free()

func test_entity_postprocessors() -> void:
	var called_count := 0
	var postprocessor := func(entity: Entity):
		called_count += 1

	ECS.entity_postprocessors.append(postprocessor)

	var test_world = World.new()
	var old_world = ECS.world
	ECS.world = test_world

	var entity = Entity.new()
	test_world.add_entity(entity)
	test_world.remove_entity(entity)

	assert_int(called_count).is_equal(1)

	# Clean up
	ECS.entity_postprocessors.erase(postprocessor)
	ECS.world = old_world
	test_world.free()

func test_serialize_save_deserialize() -> void:
	ECS.world = world
	var e1 = Entity.new()
	e1.add_component(C_Position.new())
	world.add_entity(e1)

	var query = world.query.with_all([C_Position])
	var data = ECS.serialize(query)
	assert_object(data).is_not_null()

	var temp_file = "user://test_ecs_save.tres"
	var success = ECS.save(data, temp_file)
	assert_bool(success).is_true()

	var entities = ECS.deserialize(temp_file)
	assert_int(entities.size()).is_equal(1)

	# Clean up temp file
	DirAccess.remove_absolute(temp_file)
	# Entities returned from deserialize are newly created Nodes
	for e in entities:
		e.free()
