extends RefCounted
class_name DiagnosticList_Diagnostic


enum Severity {
    Error,
    Warning,
    Info,
    Hint,
}

## Represents the file path as res:// path
@export var res_uri: StringName
@export var line_start: int  # zero-based
@export var column_start: int  # zero-based
@export var severity: Severity
@export var message: String

var _filename: StringName

func get_filename() -> StringName:
    if _filename.is_empty():
        _filename = StringName(res_uri.get_file())
    return _filename


