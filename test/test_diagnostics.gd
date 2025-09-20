extends DiagnosticListTest


func test_diagnostics() -> void:
    var client := await _connect_client()
    var pack := await _get_diagnostics(client, TEST_GD_FILE_WITH_DIAGNOSTICS)
    var diagnostics := pack.diagnostics

    assert_eq(pack.res_uri, TEST_GD_FILE_WITH_DIAGNOSTICS)
    _assert_test_gd_diagnostics(diagnostics)


func test_special_chars() -> void:
    var client := await _connect_client()
    var pack := await _get_diagnostics(client, "res://test_files/special_chars.gd")
    var diagnostics := pack.diagnostics

    assert_signal_not_emitted(client, "on_jsonrpc_error")
    assert_eq(diagnostics.size(), 0)
