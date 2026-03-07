---
trigger: layered mock, integration test mock, scan_package mock, mock all layers
---
# Layered Architecture Mock Strategy

When a function calls multiple layers sequentially (e.g., `scan_package()` calls `scan_layer1`, `scan_layer2`, `scan_layer3a`):

1. **Unit tests for each layer**: Test each `scan_layerN()` function independently, mocking only that layer's external dependencies.
2. **Integration tests for the orchestrator**: When testing `scan_package()`, mock **all** layer boundaries (e.g., `get_rd_db`, `resolve_function`) even if only testing Layer 1 behavior — otherwise Layer 2/3 code paths emit warnings or errors from unmocked dependencies.
3. **Update mocks when adding layers**: Adding a new layer to the orchestrator requires updating the shared mock helper (e.g., `with_scan_mocks`) in integration tests.

**Anti-pattern**: Testing `scan_package()` without mocking downstream layers, assuming "Layer 1 tests don't need Layer 2 mocks."
