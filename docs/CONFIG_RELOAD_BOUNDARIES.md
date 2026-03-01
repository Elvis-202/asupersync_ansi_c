# Config Hot-Reload Boundaries (bd-3vt.9)

## Summary

Defines which `asx_runtime_config` fields are safe to modify during execution
and provides atomic reload with validation and rollback.

## Field Classification

| Field | Class | Rationale |
|-------|-------|-----------|
| `size` | FROZEN_INIT | ABI compatibility sentinel |
| `wait_policy` | RELOADABLE | Idle strategy, no semantic impact |
| `leak_response` | RELOADABLE | Diagnostic escalation only |
| `leak_escalation` | RELOADABLE | Diagnostic threshold + escalation |
| `finalizer_poll_budget` | RELOADABLE | Advisory finalization cap |
| `finalizer_time_budget_ns` | RELOADABLE | Advisory finalization timeout |
| `finalizer_escalation` | RELOADABLE | Diagnostic escalation on budget exhaust |
| `max_cancel_chain_depth` | RESTART_REQUIRED | Existing chains may exceed new limit |
| `max_cancel_chain_memory` | RESTART_REQUIRED | Existing allocations may exceed new cap |

Classification taxonomy:

- **FROZEN_COMPILE**: Compile-time only (profiles, deterministic mode)
- **FROZEN_INIT**: Set once at hook install; changes rejected at reload
- **RELOADABLE**: Safe to change mid-run; applied atomically
- **RESTART_REQUIRED**: Needs full runtime reset to take effect safely

## Reload Protocol

1. Caller prepares new config via `asx_runtime_config_init()`
2. Caller modifies only RELOADABLE fields
3. `asx_config_reload()` validates all fields then applies atomically
4. If validation fails, no changes are applied (rollback guarantee)

## Validation Strategy

Field-level byte comparison using the descriptor table. Each field's offset
and size are computed via `offsetof()` / `sizeof()` at compile time. Changed
fields are checked against their reload class:

- RELOADABLE: allowed
- FROZEN_*: returns `ASX_E_CONFIG_FROZEN`
- RESTART_REQUIRED: returns `ASX_E_CONFIG_RESTART_REQ`

First offending field name is reported via `rejection_field` out-parameter.

## Error Codes

| Code | Value | String |
|------|-------|--------|
| `ASX_E_CONFIG_FROZEN` | 1600 | "config field is frozen" |
| `ASX_E_CONFIG_RESTART_REQ` | 1601 | "config field requires restart" |

## Test Coverage

27 tests across 8 categories:

- Field classification (9): every known field + unknown field default
- Initial load (3): success, null state, null config
- Reload success (3): wait_policy, leak_response, finalizer_budget
- Reload rejection (3): frozen field, 2x restart-required fields
- Rollback (1): mixed reloadable + frozen change rolls back entirely
- Edge cases (3): reload before load, validate before load, identical reload
- Field table (2): count matches struct, all offsets/sizes valid
- Safety (2): null safety, sequential reloads preserve cumulative state

## Decision

**GO** — The field descriptor table approach is sound:

- Zero runtime allocation (static table, memcpy-based reload)
- Compile-time field layout verification via offsetof/sizeof
- Rollback guarantee is trivially correct (validate-then-apply)
- Introspection API enables tooling and diagnostics
- 27/27 tests pass with strict -Werror compilation
