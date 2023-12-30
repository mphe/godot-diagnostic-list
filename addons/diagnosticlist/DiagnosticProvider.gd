extends RefCounted
class_name DiagnosticList_DiagnosticProvider

## Triggered when new diagnostics for a file arrived.
signal on_publish_diagnostics(diagnostics: Array[DiagnosticList_Diagnostic])

## Triggered when all outstanding diagnostics have been received.
signal on_diagnostics_finished


class FileCache extends RefCounted:
    var content: String = ""
    var last_modified: int = -1


var _diagnostics: Array[DiagnosticList_Diagnostic] = []
var _client: DiagnosticList_LSPClient
var _script_paths: Array[String] = []
var _counts: Array[int] = [ 0, 0, 0, 0 ]
var _num_outstanding: int = 0
var _dirty: bool = true
var _refresh_time: int = 0
var _file_cache := {}  # Dict[String, FileCache]


func _init(client: DiagnosticList_LSPClient) -> void:
    _client = client
    _client.on_publish_diagnostics.connect(_on_publish_diagnostics)

    var fs := EditorInterface.get_resource_filesystem()

    # Triggered when saving, removing and moving files.
    # Also triggers whenever the user is typing or saving in an external editor using LSP.
    fs.script_classes_updated.connect(_on_script_classes_updated)

    # Triggered when the Godot window receives focus and when moving or deleting files
    fs.sources_changed.connect(_on_sources_changed)


## Refresh diagnostics for all scripts.
## Returns true on success or false when there are no updates available or when another update is
## still in progress.
func refresh_diagnostics(force: bool = false) -> bool:
    # NOTE: On first thought, it sounds smart to only update diagnostics for files that actually
    # changed (compare last modified timestamp).
    # However, a change in one file can cause errors in other files, e.g. renaming an identifier.
    # Hence, we always have to do a full update.
    # Theoretically, if there was a dependency graph of scripts, we could only update relevant
    # scripts, but this is beyond the scope of this plugin.

    # Still waiting for results from the last call
    if _num_outstanding > 0:
        return false

    # Nothing changed -> nothing to do
    if not force and not _dirty:
        return false

    print("Running diagnostic update")

    var files_modified := refresh_file_list()

    if not force and not files_modified:
        return false

    _diagnostics.clear()
    _counts = [ 0, 0, 0, 0 ]
    _num_outstanding = len(_script_paths)
    _refresh_time = Time.get_ticks_usec()

    if _num_outstanding > 0:
        # var file_time := Time.get_ticks_usec()
        for file in _script_paths:
            _client.update_diagnostics(file, _file_cache[file].content)
            # _client.update_diagnostics(file, FileAccess.get_file_as_string(file))
            # _client.update_diagnostics(file, (load(file) as GDScript).source_code)
        _client.enable_processing()
        # file_time = Time.get_ticks_usec() - file_time
        # print("file time: ", file_time / 1000.0, " ms")
    else:
        _finish_update()

    # If everything was succesful, reset dirty flag
    _dirty = false
    return true


func _finish_update() -> void:
    # NOTE: When parsing scripts using LSP, the script_classes_updated signal will be fired multiple
    # times by the engine without any actual changes.
    # Hence, to prevent false positive dirty flags, reset _dirty back to false when the diagnsotic
    # update is finished.
    # FIXME: It might happen that the user makes a change while diagnostics are still refreshing,
    # In this case, the dirty flag would still be resetted, even though it shouldn't.
    # This is essentially a tradeoff between efficiency and accuracy.
    # As I find this exact scenario unlikely to occur regularily, I prefer the more efficient
    # implementation of updating less often.
    _dirty = false

    _refresh_time = Time.get_ticks_usec() - _refresh_time
    on_diagnostics_finished.emit()


## Rescan the project for script files
## Returns true when there have been changes, otherwise false.
func refresh_file_list() -> bool:
    _script_paths = _gather_scripts("res://")

    var modified: bool = false

    # Update cache
    for path in _script_paths:
        var cache: FileCache = _file_cache.get(path)
        var last_modified: int = FileAccess.get_modified_time(path)

        if not cache:
            cache = FileCache.new()
            _file_cache[path] = cache

        if cache.last_modified != last_modified:
            cache.last_modified = last_modified
            cache.content = FileAccess.get_file_as_string(path)
            modified = true

    # One or more files were deleted
    if _file_cache.size() > _script_paths.size():
        modified = true

        # TODO: Could be more efficient, but happens not so often
        for path: String in _file_cache.keys():
            if not _script_paths.has(path):
                _file_cache.erase(path)

    return modified


func _on_script_resource_changed(path: String) -> void:
    print(path, " changed")


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


func _on_sources_changed(_exist: bool) -> void:
    _dirty = true


func _on_script_classes_updated() -> void:
    # NOTE: When using an external editor over LSP, the engine will constantly emit the
    # script_classes_updated signal whenever the user is typing.
    # In those cases it is useless to perform an update, as nothing actually changed.
    # We also cannot safely determine when the user has saved a file except by comparing file
    # modification timestamps.
    #
    # However, whenever the Godot window receives focus, a sources_changed signal is fired.
    #
    # Hence, to prevent unnecessary amounts of updates when using external editors,
    # check whether the Godot window has focus and if it doesn't, ignore the signal, as the user is
    # likely typing in an external editor.
    #
    # When using the internal editor, script_classes_updated will only be fired upon saving.
    # Hence, when the signal arrives and the Godot window has focus, an update should be performed.
    if EditorInterface.get_base_control().get_window().has_focus():
        _dirty = true


func _on_publish_diagnostics(diagnostics: Array[DiagnosticList_Diagnostic]) -> void:
    _diagnostics.append_array(diagnostics)
    _num_outstanding -= 1

    # Increase new diagnostic counts
    for diag in diagnostics:
        _counts[diag.severity] += 1

    on_publish_diagnostics.emit(diagnostics)

    if _num_outstanding == 0:
        _client.disable_processing()
        _finish_update()


func _gather_scripts(searchpath: String) -> Array[String]:
    var root := DirAccess.open(searchpath)

    if not root:
        push_error("Failed to open directory: ", searchpath)

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
