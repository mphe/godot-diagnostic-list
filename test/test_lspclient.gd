extends DiagnosticListTest


func test_connect() -> void:
    var client := await _connect_client()

    assert_true(client.is_lsp_connected())

    assert_signal_emitted(client, "on_connected")
    assert_signal_emitted(client, "on_initialized")

    assert_signal_emit_count(client, "on_connected", 1)
    assert_signal_emit_count(client, "on_initialized", 1)

    assert_signal_not_emitted(client, "on_jsonrpc_error")

    client.disconnect_lsp()


func test_jsonrpc_error() -> void:
    var client := await _connect_client()

    client._send_request("asdf", {})

    await wait_for_signal(client.on_jsonrpc_error, 3)

    assert_signal_emit_count(client, "on_jsonrpc_error", 1)
    assert_push_error(2)

    client.disconnect_lsp()


func test_update_diagnostics() -> void:
    var client := await _connect_client()

    client.update_diagnostics("file.gd", "extends Node\n")

    await wait_for_signal(client.on_publish_diagnostics, 3)

    assert_signal_emit_count(client, "on_publish_diagnostics", 1)
    assert_signal_not_emitted(client, "on_jsonrpc_error")

    client.disconnect_lsp()
