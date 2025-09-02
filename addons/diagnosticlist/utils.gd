@tool
extends RefCounted
class_name DiagnosticList_Utils

const ENABLE_DEBUG_LOG: bool = false


static func log_debug(text: String) -> void:
    if ENABLE_DEBUG_LOG:
        print("[DiagnosticList] ", text)


static func log_error(text: String) -> void:
    push_error("[DiagnosticList] ", text)
