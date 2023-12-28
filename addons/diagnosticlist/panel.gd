@tool
extends Control
class_name DiagnosticList_Panel

class DiagnosticTheme extends RefCounted:
    var text: String
    var icon: Texture2D
    var color: Color

    func _init(text: String, icon: Texture2D, color: Color):
        self.text = text
        self.icon = icon
        self.color = color


# This array will be filled according to each severity type defined by LSP.
# https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#diagnosticSeverity
var _severity_themes: Array[DiagnosticTheme] = [ null, null, null, null ]
var _script_icon := get_theme_icon(&"Script", &"EditorIcons")

var _btn_refresh_errors: Button
var _error_list_tree: Tree
var _script_paths: Array[String] = []
var _client: DiagnosticList_LSPClient
var _dirty: bool = true

func _enter_tree() -> void:
    _severity_themes = [
        null,
        DiagnosticTheme.new("Error", get_theme_icon(&"StatusError", &"EditorIcons"), get_theme_color(&"error_color", &"Editor")),
        DiagnosticTheme.new("Warning", get_theme_icon(&"StatusWarning", &"EditorIcons"), get_theme_color(&"warning_color", &"Editor")),
        DiagnosticTheme.new("Info", get_theme_icon(&"Popup", &"EditorIcons"), get_theme_color(&"font_color", &"Editor")),
        DiagnosticTheme.new("Hint", get_theme_icon(&"Info", &"EditorIcons"), get_theme_color(&"font_color", &"Editor")),
    ]

    _script_icon = get_theme_icon(&"Script", &"EditorIcons")

    _btn_refresh_errors = %"btn_refresh_errors"
    _error_list_tree = %"error_tree_list"

    _btn_refresh_errors.connect("pressed", force_refresh_diagnostics)

    # Disable buttons until connected to LSP
    _btn_refresh_errors.disabled = true

    _error_list_tree.columns = 3
    _error_list_tree.set_column_title(0, "Message")
    _error_list_tree.set_column_title(1, "File")
    _error_list_tree.set_column_title(2, "Line")
    # _error_list_tree.set_column_title(2, "Column")
    _error_list_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
    _error_list_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
    _error_list_tree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)
    # _error_list_tree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)
    # _error_list_tree.column_titles_visible = true
    _error_list_tree.set_column_expand(0, true)
    _error_list_tree.connect("item_activated", _item_activated)

    var fs := EditorInterface.get_resource_filesystem()
    fs.connect("script_classes_updated", func(): _dirty = true)

    set_client(_client)


func set_client(client: DiagnosticList_LSPClient) -> void:
    if _client:
        _client.disconnect("on_publish_diagnostics", _on_publish_diagnostics)

    _client = client

    if _client:
        _client.connect("on_publish_diagnostics", _on_publish_diagnostics)

    if is_inside_tree():
        _btn_refresh_errors.disabled = _client == null


func clear() -> void:
    _error_list_tree.clear()
    _error_list_tree.create_item()  # root


func force_refresh_diagnostics() -> void:
    clear()
    refresh_file_list()

    for path in _script_paths:
        _client.update_diagnostics(path)

    return


func refresh_file_list() -> void:
    var time_begin := Time.get_ticks_usec()
    _script_paths = _gather_scripts("res://")

    print("Gathered ", len(_script_paths), " script_paths in ", (Time.get_ticks_usec() - time_begin) / 1000.0, " ms")


## Expects searchpath without trailing slash
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
        var theme := _severity_themes[diag.severity]
        # entry.set_custom_color(0, theme.color)
        entry.set_text(0, diag.message)
        entry.set_icon(0, theme.icon)
        entry.set_text(1, uri)
        entry.set_text(2, "Line " + str(diag.line_start))
        entry.set_metadata(0, diag)  # Meta data is used in _item_activated to open the respective script


func _item_activated() -> void:
    var selected: TreeItem = _error_list_tree.get_selected()
    var diagnostic: DiagnosticList_LSPClient.Diagnostic = selected.get_metadata(0)
    # NOTE: Lines and columns are zero-based in LSP, but Godot expects one-based values
    EditorInterface.edit_script(load(str(diagnostic.uri)), diagnostic.line_start + 1, diagnostic.column_start + 1)
    EditorInterface.set_main_screen_editor("Script")
