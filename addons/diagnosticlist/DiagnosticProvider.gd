extends RefCounted
class_name DiagnosticList_DiagnosticProvider

## Triggered when new diagnostics for a file arrived.
signal on_publish_diagnostics(diagnostics: Array[DiagnosticList_Diagnostic])

## Triggered when all outstanding diagnostics have been received.
signal on_diagnostics_finished


var _diagnostics: Array[DiagnosticList_Diagnostic] = []
var _client: DiagnosticList_LSPClient
var _script_paths: Array[String] = []
var _counts: Array[int] = [ 0, 0, 0, 0 ]
var _num_outstanding: int = 0
var _dirty: bool = true
var _refresh_time: int = 0


func _init(client: DiagnosticList_LSPClient) -> void:
    _client = client
    _client.on_publish_diagnostics.connect(_on_publish_diagnostics)

    # Listen for script changes
    var fs := EditorInterface.get_resource_filesystem()
    fs.script_classes_updated.connect(_on_script_classes_updated)


## Refresh diagnostics for all scripts
func refresh_diagnostics() -> void:
    # NOTE: On first thought, it sounds smart to only update diagnostics for files that actually
    # changed (compare last modified timestamp).
    # However, a change in one file can cause errors in other files, e.g. renaming an identifier.
    # Hence, we always have to do a full update.
    # Theoretically, if there was a dependency graph of scripts, we could only update relevant
    # scripts, but this is beyond the scope of this plugin.

    # Still waiting for results from the last call
    if _num_outstanding > 0:
        return

    # Nothing changed -> nothing to do
    if not _dirty:
        return

    refresh_file_list()

    _diagnostics.clear()
    _counts = [ 0, 0, 0, 0 ]
    _num_outstanding = len(_script_paths)
    _refresh_time = Time.get_ticks_usec()

    if _num_outstanding > 0:
        for file in _script_paths:
            _client.update_diagnostics(file)
    else:
        _finish_update()

    # If everything was succesful, reset dirty flag
    _dirty = false


func _finish_update() -> void:
    _refresh_time = Time.get_ticks_usec() - _refresh_time
    on_diagnostics_finished.emit()


## Rescan the project for script files
func refresh_file_list() -> void:
    _script_paths = _gather_scripts("res://")


## Get the amount of diagnostics of a given severity.
func get_diagnostic_count(severity: DiagnosticList_Diagnostic.Severity) -> int:
    return _counts[severity]


## Returns all diagnostics of the project
func get_diagnostics() -> Array[DiagnosticList_Diagnostic]:
    return _diagnostics.duplicate()


## Returns the amount of microseconds between requesting the last diagnostic update and the last
## diagnostic being delivered.
func get_refresh_time_usec() -> int:
    return _refresh_time


func _on_script_classes_updated() -> void:
    _dirty = true


func _on_publish_diagnostics(diagnostics: Array[DiagnosticList_Diagnostic]) -> void:
    _diagnostics.append_array(diagnostics)
    _num_outstanding -= 1

    # Increase new diagnostic counts
    for diag in diagnostics:
        _counts[diag.severity] += 1

    on_publish_diagnostics.emit(diagnostics)

    if _num_outstanding == 0:
        _finish_update()


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
