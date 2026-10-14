extends Node
## Top-level scene: runs the overworld and swaps to a battle when a fight starts.
## (main.tscn still runs a bare battle with the enemy-select screen, for quick testing.)

const OverworldScript := preload("res://overworld.gd")
const BattleScript := preload("res://battle.gd")

var ow: Node2D
var battle: Node2D = null
var fade: ColorRect


func _ready() -> void:
	ow = OverworldScript.new()
	add_child(ow)
	ow.encounter.connect(_on_encounter)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.size = Vector2(640, 480)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)


func _fade_to(alpha: float, secs: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(fade, "color:a", alpha, secs)
	await tw.finished


func _on_encounter(id: String) -> void:
	await _fade_to(1.0, 0.35)
	ow.visible = false
	ow.set_process(false)
	ow.set_process_input(false)
	BattleScript.next_enemy = id
	battle = BattleScript.new()
	battle.embedded = true
	battle.fight_over.connect(func(outcome: String) -> void: _on_fight_over(id, outcome))
	add_child(battle)
	await _fade_to(0.0, 0.35)


func _on_fight_over(id: String, outcome: String) -> void:
	await _fade_to(1.0, 0.35)
	battle.queue_free()
	battle = null
	BattleScript.next_enemy = ""
	ow.visible = true
	ow.set_process(true)
	ow.set_process_input(true)
	ow.resume(id, outcome)
	await _fade_to(0.0, 0.35)
