extends "res://test/BaseTest.gd"


func test_ignore() -> void:
    var provider := await _create_provider()
    provider.set_additional_ignore_dirs([ "res://test", "res://addons" ])
    watch_signals(provider)

    assert_true(provider.refresh_file_list())

    provider.refresh_diagnostics(true)

    assert_true(provider.is_updating())

    await wait_for_signal(provider.on_diagnostics_finished, 3)

    # Should only provide diagnostics for foo.gd, special_chars.gd and test.gd
    assert_signal_emit_count(provider, "on_publish_diagnostics", 3)
    assert_signal_emit_count(provider, "on_update_progress", 3)

    assert_eq(provider.get_diagnostic_count(DiagnosticList_Diagnostic.Severity.Error), 1)
    assert_eq(provider.get_diagnostic_count(DiagnosticList_Diagnostic.Severity.Warning), 2)
    assert_eq(provider.get_diagnostic_count(DiagnosticList_Diagnostic.Severity.Info), 0)

    assert_false(provider.refresh_file_list())
    assert_false(provider.is_updating())
    assert_false(provider.refresh_diagnostics())

    _assert_test_gd_diagnostics(provider.get_diagnostics())
