extends Node3D

var particle_count: int = 5
var particle_size: float = 0.1
var spread_force: float = 3.0
var lifetime: float = 0.5

static var _shared_mesh: SphereMesh = null
static var _material_cache: Dictionary = {}

var _color: Color = Color.RED
var _elapsed: float = 0.0
var _velocities: PackedVector3Array = []
var _positions: PackedVector3Array = []
var _multimesh_instance: MultiMeshInstance3D = null


func setup(color: Color) -> void:
	_color = color


func _ready() -> void:
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
	var shared_material: Material = _get_or_create_material(_color)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _shared_mesh
	multimesh.instance_count = particle_count
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.material_override = shared_material
	_multimesh_instance.multimesh = multimesh
	add_child(_multimesh_instance)

	_positions.resize(particle_count)
	_velocities.resize(particle_count)
	for i in range(particle_count):
		_positions[i] = Vector3.ZERO
		_velocities[i] = Vector3(
			randf_range(-1, 1),
			randf_range(0.5, 1.5),
			randf_range(-1, 1)
		).normalized() * spread_force
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * particle_size), _positions[i]))


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	var progress: float = _elapsed / lifetime
	var scale_factor: float = 1.0 - progress
	var multimesh: MultiMesh = _multimesh_instance.multimesh
	for i in range(particle_count):
		_positions[i] += _velocities[i] * delta
		_velocities[i].y -= 9.8 * delta
		multimesh.set_instance_transform(
			i,
			Transform3D(Basis().scaled(Vector3.ONE * particle_size * scale_factor), _positions[i])
		)


func _get_or_create_material(color: Color) -> Material:
	var cache_key: String = color.to_html(true)
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material_cache[cache_key] = material
	return material