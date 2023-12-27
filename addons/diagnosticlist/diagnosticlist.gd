@tool
extends EditorPlugin

const panel_scene = preload("res://addons/diagnosticlist/panel.tscn")

var _dock: DiagnosticList_Panel
var _client: DiagnosticList_LSPClient
var _script_paths: Array[String] = []


func _enter_tree() -> void:
    # var fs := EditorInterface.get_resource_filesystem()
    # fs.resources_reimported.connect(func(res): print("reimport: ", res))
    # fs.resources_reload.connect(func(res): print("reload: ", res))
    # fs.script_classes_updated.connect(func(): print("script classes update"))
    # fs.sources_changed.connect(func(exist): print("sources changed"))

    _client = DiagnosticList_LSPClient.new()
    _client.connect("on_initialized", _on_lsp_initialized)
    _client.connect_lsp()

    _dock = panel_scene.instantiate()
    # _dock.set_client(_client)
    add_control_to_bottom_panel(_dock, "Diagnostics")


func _exit_tree() -> void:
    remove_control_from_bottom_panel(_dock)
    _dock.free()
    _client.disconnect_lsp()


func _on_lsp_initialized() -> void:
    _dock.set_client(_client)
