extends RefCounted
class_name DiagnosticList_LSPClient

signal on_initialized
signal on_connected
signal on_publish_diagnostics(params: Dictionary)

const TICK_INTERVAL_SECONDS: float = 1.0

@export var print_debug: bool = false

var _jsonrpc := JSONRPC.new()
var _client := StreamPeerTCP.new()
var _id: int = 0


func disconnect_lsp() -> void:
    log_info("Disconnecting from LSP")
    _client.disconnect_from_host()


func connect_lsp() -> void:
    var settings := EditorInterface.get_editor_settings()
    var port: int = settings.get("network/language_server/remote_port")
    var host: String = settings.get("network/language_server/remote_host")

    var err := _client.connect_to_host(host, port)

    if err != OK:
        log_error("Failed to connect to LSP server: %s" % err)

    _restart_timer()


func _restart_timer() -> void:
    var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(TICK_INTERVAL_SECONDS, true, false, true)
    timer.connect("timeout", _on_tick)


func _on_tick() -> void:
    if not _update_status():
        disconnect_lsp()
        return

    while _client.get_available_bytes():
        var json := _read_data()

        if json:
            log_debug("Received message:\n%s" % json)

        _handle_response(json)

    _restart_timer()


## Updates the current socket status and returns true when the main loop should continue.
func _update_status() -> bool:
    var last_status := _client.get_status()

    _client.poll()

    var status := _client.get_status()

    match status:
        StreamPeerTCP.STATUS_NONE:
            return false
        StreamPeerTCP.STATUS_ERROR:
            log_error("StreamPeerTCP error")
            return false
        StreamPeerTCP.STATUS_CONNECTING:
            pass
        StreamPeerTCP.STATUS_CONNECTED:
            # First time connected -> run initialization
            if last_status != status:
                log_info("Connected to LSP")
                emit_signal("on_connected")
                _initialize()

    return true


func _read_data() -> Dictionary:
    # NOTE:
    # At the moment, Godot only ever transmits headers with a single Content-Length field and
    # likewise expects headers with only one field (see gdscript_language_protocol.cpp, line 61).
    # Hence, the following also assumes there is only the Content-Length field in the header.
    # If Godot ever starts sending additional fields, this will break.

    var header := _read_header().strip_edges()
    var content_length = int(header.substr(len("Content-Length")))
    var content := _read_content(content_length)
    var json := JSON.parse_string(content)

    if not json:
        log_error("Failed to parse JSON: %s" % content)
        return {}

    return json


func _read_content(length: int) -> String:
    var data := _client.get_data(length)

    if data[0] != OK:
        log_error("Failed to read content: %s" % error_string(data[0]))
        return ""
    else:
        var buf: PackedByteArray = data[1]
        return buf.get_string_from_utf8()


func _read_header() -> String:
    var buf := PackedByteArray()
    var char_r := "\r".unicode_at(0)
    var char_n := "\n".unicode_at(0)

    while true:
        var data := _client.get_data(1)

        if data[0] != OK:
            log_error("Failed to read header: %s" % error_string(data[0]))
            return ""
        else:
            buf.push_back(data[1][0])

        var bufsize := buf.size()

        if bufsize >= 4 \
                and buf[bufsize - 1] == char_n \
                and buf[bufsize - 2] == char_r \
                and buf[bufsize - 3] == char_n \
                and buf[bufsize - 4] == char_r:
            return buf.get_string_from_ascii()

    # This should never happen but the GDScript compiler complains "not all code paths return a value"
    return ""


func _handle_response(json: Dictionary) -> void:
    # Diagnostics received
    if json.get("method") == "textDocument/publishDiagnostics":
        emit_signal("on_publish_diagnostics", json["params"])

    # Initialization response
    elif json.get("id") == 0:
        _send_notification("initialized", {})
        emit_signal("on_initialized")


func _send_request(method: String, params: Dictionary) -> int:
    _send(_jsonrpc.make_request(method, params, _id))
    _id += 1
    return _id - 1


func _send_notification(method: String, params: Dictionary) -> void:
    _send(_jsonrpc.make_notification(method, params))


func _send(json: Dictionary) -> void:
    var content := JSON.stringify(json, "", false)
    var content_bytes := content.to_utf8_buffer()
    var header := "Content-Length: %s\r\n\r\n" % len(content)
    var header_bytes := header.to_ascii_buffer()
    log_debug("Sending message (length: %s): %s" % [ len(content), content ])
    _client.put_data(header_bytes + content_bytes)


func _initialize() -> void:
    var root_path := ProjectSettings.globalize_path("res://")

    _send_request("initialize", {
        "processId": null,
        "rootPath": root_path,
        "rootUri": "file://" + root_path,
        "capabilities": {
            "textDocument": {
                "publishDiagnostics": {
                    # "relatedInformation": true,
                    # "versionSupport": true,
                    # "tagSupport": {
                    #     "valueSet": [ 1, 2 ]
                    # },
                    # "codeDescriptionSupport": true,
                },
            },
        },
    })


func update_diagnostics(file_path: String) -> void:
    var uri := "file://" + ProjectSettings.globalize_path(file_path).simplify_path()

    _send_notification("textDocument/didOpen", {
        "textDocument": {
            "uri": uri,
            "text": FileAccess.get_file_as_string(file_path),
            "languageId": "gdscript",  # Unused by Godot LSP
            "version": 0,  # Unused by Godot LSP
        }
    })

    # Technically, the Godot LS does nothing on didClose, but send it anyway in case it changes in the future.
    _send_notification("textDocument/didClose", {
        "textDocument": {
            "uri": uri
        }
    })


func log_info(text: String) -> void:
    print("[DiagnosticList] ", text)


func log_debug(text: String) -> void:
    if print_debug:
        log_info(text)

func log_error(text: String) -> void:
    push_error("[DiagnosticList] ", text)
