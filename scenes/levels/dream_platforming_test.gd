extends Node2D
## Graybox platforming test level.
##
## A future full level will play an Intro (walking, story triggers, camera
## performance) before platforming. That is intentionally NOT implemented now;
## we expose a LevelPhase enum as the extension point and start directly in
## PLATFORMING. No fake story / no cutscene manager is created here.

enum LevelPhase { INTRO, PLATFORMING, COMPLETE }

## Set in the Inspector. Defaults to PLATFORMING for this test.
@export var start_phase: LevelPhase = LevelPhase.PLATFORMING

@onready var _player: CharacterBody2D = $Player
@onready var _spawn: Marker2D = $World/SpawnPoint
@onready var _death_zone: Area2D = $World/DeathZone
@onready var _camera: Camera2D = $Camera2D

var _phase: LevelPhase = LevelPhase.PLATFORMING


func _ready() -> void:
	_player.set_spawn_point(_spawn.global_position)
	_player.global_position = _spawn.global_position
	_death_zone.body_entered.connect(_on_death_zone_entered)
	_enter_phase(start_phase)


func _process(_delta: float) -> void:
	# Simple follow camera (kept at level root per the required structure).
	_camera.global_position = _player.global_position


func _enter_phase(phase: LevelPhase) -> void:
	_phase = phase
	match _phase:
		LevelPhase.INTRO:
			# Intro reserved for later; for now skip straight to platforming.
			_enter_phase(LevelPhase.PLATFORMING)
		LevelPhase.PLATFORMING:
			pass
		LevelPhase.COMPLETE:
			pass


func _on_death_zone_entered(body: Node) -> void:
	if body == _player:
		print("[Level] Player entered death zone — respawning.")
		_player.respawn()
