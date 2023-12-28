@tool
extends Control
class_name DiagnosticList_Panel

class DiagnosticSeveritySettings extends RefCounted:
    var text: String
    var icon: Texture2D
    var color: Color
    var hide: bool
    var count: int = 0

    func _init(text_: String, icon_id: StringName, color_id: StringName, hide_: bool) -> void:
        self.text = text_
        self.icon = EditorInterface.get_editor_theme().get_icon(icon_id, &"EditorIcons")
        self.color = EditorInterface.get_editor_theme().get_color(color_id, &"Editor")
        self.hide = hide_


@onready var _btn_refresh_errors: Button = %"btn_refresh_errors"
@onready var _error_list_tree: Tree = %"error_tree_list"
@onready var _cb_auto_refresh: CheckBox = %"cb_auto_refresh"
@onready var _cb_group_by_file: CheckBox = %"cb_group_by_file"

# This array will be filled according to each severity type to allow direct indexing
@onready var _filter_buttons: Array[Button] = [
    %"btn_filter_errors",
    %"btn_filter_warnings",
    %"btn_filter_infos",
    %"btn_filter_hints",
]

# This array will be filled according to each severity type to allow direct indexing
@onready var _severity_settings: Array[DiagnosticSeveritySettings] = [
    DiagnosticSeveritySettings.new("Error",   &"StatusError",   &"error_color",   not _filter_buttons[0].button_pressed),
    DiagnosticSeveritySettings.new("Warning", &"StatusWarning", &"warning_color", not _filter_buttons[1].button_pressed),
    DiagnosticSeveritySettings.new("Info",    &"Popup",         &"font_color",    not _filter_buttons[2].button_pressed),
    DiagnosticSeveritySettings.new("Hint",    &"Info",          &"font_color",    not _filter_buttons[3].button_pressed),
]

@onready var _script_icon: Texture2D = get_theme_icon(&"Script", &"EditorIcons")

var _script_paths: Array[String] = []
var _client: DiagnosticList_LSPClient
var _dirty: bool = true


func _ready() -> void:
    # Setup controls
    _btn_refresh_errors.connect("pressed", force_refresh_diagnostics)
    _btn_refresh_errors.disabled = true  # Disable button until connected to LSP

    for i in len(_filter_buttons):
        var btn: Button = _filter_buttons[i]
        var severity := _severity_settings[i]
        # btn.theme_type_variation = &"EditorLogFilterButton"
        btn.icon = severity.icon
        btn.connect("toggled", _on_filter_toggled.bind(severity))

    # These kinds of diagnostics do not exist in Godot LSP, so hide them for now.
    _filter_buttons[DiagnosticList_LSPClient.DiagnosticSeverity.Info].hide()
    _filter_buttons[DiagnosticList_LSPClient.DiagnosticSeverity.Hint].hide()

    _error_list_tree.columns = 3
    _error_list_tree.set_column_title(0, "Message")
    _error_list_tree.set_column_title(1, "File")
    _error_list_tree.set_column_title(2, "Line")
    _error_list_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
    _error_list_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
    _error_list_tree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)
    _error_list_tree.set_column_expand(0, true)
    _error_list_tree.connect("item_activated", _item_activated)

    # Listen for file system changes
    var fs := EditorInterface.get_resource_filesystem()
    fs.connect("script_classes_updated", func(): _dirty = true)

    # Refresh client
    set_client(_client)


func set_client(client: DiagnosticList_LSPClient) -> void:
    if _client:
        _client.disconnect("on_publish_diagnostics", _on_publish_diagnostics)

    _client = client

    if _client:
        _client.connect("on_publish_diagnostics", _on_publish_diagnostics)

    if is_inside_tree():
        _btn_refresh_errors.disabled = _client == null


func _clear() -> void:
    _error_list_tree.clear()
    _error_list_tree.create_item()  # root

    for i in _severity_settings:
        i.count = 0


func force_refresh_diagnostics() -> void:
    _clear()
    refresh_file_list()

    for path in _script_paths:
        _client.update_diagnostics(path)

    return


func refresh_file_list() -> void:
    var time_begin := Time.get_ticks_usec()
    _script_paths = _gather_scripts("res://")

    print("Gathered ", len(_script_paths), " script_paths in ", (Time.get_ticks_usec() - time_begin) / 1000.0, " ms")


func _gather_scripts(searchpath: String) -> Array[String]:
    var root := DirAccess.open(searchpath)

    if not root:
        print("Failed to open directory: ", searchpath)

    var paths: Array[String] = []

    if root.file_exists(".gdignore"):
        return paths

    root.include_navigational = false
    root.list_dir_begin()

    var fname := root.get_next()

    var root_path := root.get_current_dir()

    while not fname.is_empty():
        var path := root_path.path_join(fname)

        if root.current_is_dir():
            paths.append_array(_gather_scripts(path))
        elif fname.ends_with(".gd"):
            paths.append(path)

        fname = root.get_next()

    root.list_dir_end()

    return paths


func _on_publish_diagnostics(diagnostics: Array[DiagnosticList_LSPClient.Diagnostic]) -> void:
    if diagnostics.is_empty():
        return

    var item: TreeItem = _error_list_tree.create_item()
    var uri := diagnostics[0].uri.replace("res://", "")
    item.set_text(0, uri)
    item.set_icon(0, _script_icon)
    item.set_metadata(0, diagnostics[0])

    for diag in diagnostics:
        var entry: TreeItem = _error_list_tree.create_item(item)
        var severity_setting := _severity_settings[diag.severity]
        severity_setting.count += 1
        # entry.set_custom_color(0, theme.color)
        entry.set_text(0, diag.message)
        entry.set_icon(0, severity_setting.icon)
        entry.set_text(1, uri)
        entry.set_text(2, "Line " + str(diag.line_start))
        entry.set_metadata(0, diag)  # Meta data is used in _item_activated to open the respective script
        _filter_buttons[diag.severity].text = str(severity_setting.count)


func _item_activated() -> void:
    var selected: TreeItem = _error_list_tree.get_selected()
    var diagnostic: DiagnosticList_LSPClient.Diagnostic = selected.get_metadata(0)
    # NOTE: Lines and columns are zero-based in LSP, but Godot expects one-based values
    EditorInterface.edit_script(load(str(diagnostic.uri)), diagnostic.line_start + 1, diagnostic.column_start + 1)
    EditorInterface.set_main_screen_editor("Script")


func _on_filter_toggled(toggled_on: bool, severity_setting: DiagnosticSeveritySettings) -> void:
    severity_setting.hide = not toggled_on
