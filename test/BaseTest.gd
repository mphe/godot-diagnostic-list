extends GutTest


var _pack_buffer: DiagnosticList_Diagnostic.Pack


func _create_provider() -> DiagnosticList_DiagnosticProvider:
    var client := await _connect_client()
    return DiagnosticList_DiagnosticProvider.new(client)


## Create a new LSP client object, connect to LSP and wait until connected
func _connect_client() -> DiagnosticList_LSPClient:
    var client := DiagnosticList_LSPClient.new(add_child_autoqfree(Node.new()))
    watch_signals(client)

    assert_false(client.is_lsp_connected())

    client.connect_lsp_at("127.0.0.1", 6008)
    await wait_for_signal(client.on_initialized, 3)

    return client


func _get_diagnostics(client: DiagnosticList_LSPClient, res_path: String) -> DiagnosticList_Diagnostic.Pack:
    client.on_publish_diagnostics.connect(_on_publish_diagnostics)

    client.update_diagnostics(res_path, FileAccess.get_file_as_string(res_path))
    await client.on_publish_diagnostics

    client.on_publish_diagnostics.disconnect(_on_publish_diagnostics)

    var pack := _pack_buffer
    _pack_buffer = null

    var diagnostics := pack.diagnostics

    assert_eq(pack.res_uri, res_path)

    for d in diagnostics:
        assert_eq(d.res_uri, pack.res_uri)
        assert_eq(d.get_filename(), res_path.get_file())

    return pack


func _on_publish_diagnostics(pack: DiagnosticList_Diagnostic.Pack) -> void:
    _pack_buffer = pack


func _diagnostic_sort(a: DiagnosticList_Diagnostic, b: DiagnosticList_Diagnostic) -> bool:
    return a.line_start < b.line_start \
        and a.severity < b.severity


func _assert_test_gd_diagnostics(diagnostics: Array[DiagnosticList_Diagnostic]) -> void:
    ## Sort diagnostics by line and severity for easier validy checking
    diagnostics.sort_custom(_diagnostic_sort)

    assert_eq(diagnostics.size(), 3)

    var err_not_declared := diagnostics[0]
    assert_eq(err_not_declared.line_start, 5)
    assert_eq(err_not_declared.column_start, 4)
    assert_eq(err_not_declared.severity, DiagnosticList_Diagnostic.Severity.Error)

    var warn_standalone := diagnostics[1]
    assert_eq(warn_standalone.line_start, 5)
    assert_eq(warn_standalone.column_start, 4)
    assert_eq(warn_standalone.severity, DiagnosticList_Diagnostic.Severity.Warning)

    var warn_unused := diagnostics[2]
    assert_eq(warn_unused.line_start, 8)
    assert_eq(warn_unused.column_start, 0)
    assert_eq(warn_unused.severity, DiagnosticList_Diagnostic.Severity.Warning)
