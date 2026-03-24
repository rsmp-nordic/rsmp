# Plan: Complete Transition to TrafficControllerProxy

## Current State

- `@site` in TLC tests IS already `RSMP::TLC::TrafficControllerProxy` — the supervisor's `build_proxy` selects it when `sxl == 'tlc'` (in `lib/rsmp/node/supervisor/supervisor.rb`)
- Proxy currently has: `set_timeplan` (M0002), `fetch_signal_plan` (request S0014), `subscribe_to_timeplan`, `@timeplan`/`@timeplan_source` caching, `security_code_for(level)` (private)
- ~40+ command/status methods still live in validator's `CommandHelpers`/`StatusHelpers` modules
- Tests use `prepare(task, site)` to set `@task`/`@site`, then call flat helper methods
- `signal_plans_spec.rb` partially migrated: calls `site.set_timeplan` and `site.fetch_signal_plan` directly
- Security codes: proxy reads `@site_settings['security_codes']` (private `security_code_for`); validator reads `Validator.get_config('secrets', 'security_codes', 2)` — mismatch to resolve via initializer

## Design Decisions

- Both low-level `set_*` AND high-level `switch_*` methods in proxy
- `wait_for_status` moves to proxy (validator keeps thin config-aware wrapper)
- Security codes passed via initializer (from site settings in constructor options)

---

## Phase 1 — rsmp gem: Security codes in initializer + proxy infrastructure

1. Verify `security_code_for(level)` works cleanly from `@site_settings['security_codes']`; document the expected initializer options key.
2. Add `wait_for_status(description, status_list, update_rate: 0, timeout: nil, component_id: nil)` to `TrafficControllerProxy` — subscribe_to_status with `collect!:`, ensure-block unsubscribe. Move `use_soc?` version check into proxy; default timeout from `@timeouts['command']`, default component to `main.c_id`; add `sOc: true` if core version >= 3.1.5.

## Phase 2 — rsmp gem: All low-level `set_*` M-code methods

Add to `TrafficControllerProxy`, all modeled after existing `set_timeplan` pattern:

| Method | M-code | Notes |
|--------|--------|-------|
| `set_functional_position(status, timeout_minutes: 0, options: {})` | M0001 | intersection: 0 |
| `set_traffic_situation(situation, options: {})` | M0003 | status: 'True' |
| `unset_traffic_situation(options: {})` | M0003 | status: 'False', traficsituation: '1' |
| `set_emergency_route(route:, active:, options: {})` | M0005 | active: true/false → 'True'/'False' |
| `set_input(input:, status:, options: {})` | M0006 | |
| `set_fixed_time(status, options: {})` | M0007 | |
| `force_detector_logic(component_id, status:, mode:, options: {})` | M0008 | component_id != main |
| `order_signal_start(component_id, options: {})` | M0010 | component_id = signal group |
| `order_signal_stop(component_id, options: {})` | M0011 | component_id = signal group |
| `set_inputs(status, options: {})` | M0013 | bit pattern |
| `set_dynamic_bands(plan:, status:, options: {})` | M0014 | |
| `set_offset(plan:, offset:, options: {})` | M0015 | |
| `set_week_table(status, options: {})` | M0016 | |
| `set_day_table(status, options: {})` | M0017 | |
| `set_cycle_time(plan:, cycle_time:, options: {})` | M0018 | |
| `force_input(input:, status:, value:, options: {})` | M0019 | |
| `force_output(output:, status:, value:, options: {})` | M0020 | |
| `set_trigger_level(status, options: {})` | M0021 | |
| `set_dynamic_bands_timeout(status, options: {})` | M0023 | |
| `set_security_code(level:, old_code:, new_code:, options: {})` | M0103 | no security_code_for |
| `set_clock(clock, options: {})` | M0104 | security level 1 |

## Phase 3 — rsmp gem: `confirm:` option on `set_*` methods

Instead of separate `switch_*` methods, each `set_*` method accepts a `confirm:` option that, when present, waits for the expected status confirmation after sending the command. This mirrors the `collect:`/`collect!:` pattern already used by `send_command` via `send_and_optionally_collect`:

- `confirm: {timeout: 10}` — send command then wait for confirming status; return without raising on timeout
- `confirm!: {timeout: 10}` — same but raise on timeout/error (bang variant, like `collect!:`)
- No `confirm` key — send command only, return immediately (current default behaviour)

**Example usage:**
```ruby
@site.set_timeplan(2, confirm!: { timeout: 10 })
@site.set_functional_position('YellowFlash', confirm: { timeout: 30 })
```

**Implementation pattern** (same shape as `send_and_optionally_collect`):
```ruby
def set_timeplan(plan_nr, options: {})
  # ... build command_list ...
  result = send_command main.c_id, command_list, @timeouts.merge(options)
  confirm_options = options[:confirm] || options[:confirm!]
  if confirm_options
    status = wait_for_status(
      "plan #{plan_nr}",
      [{ 'sCI' => 'S0014', 'n' => 'status', 's' => plan_nr.to_s }],
      **confirm_options
    )
    status.ok! if options[:confirm!]
  end
  result
end
```

**Confirmation status per method:**

| Method | Confirms via |
|--------|--------------|
| `set_timeplan(plan)` | S0014 `status == plan` |
| `set_traffic_situation(situation)` | S0015 `status == situation` |
| `unset_traffic_situation()` | S0015 `status == '1'` (or False) |
| `set_functional_position('YellowFlash')` | S0011 `/^True(,True)*$/` |
| `set_functional_position('Dark')` | S0007 `/^False(,False)*$/` |
| `set_functional_position('NormalControl')` | S0007 `/^True(,True)*$/` + S0011 `/^False(,False)*$/` + S0005 `'False'` |
| `set_fixed_time(status)` | S0009 `/^#{status}(,#{status})*$/` |
| `set_emergency_route(route:, active:)` | S0006 `status == active` |
| `force_input(input:, status:, value:)` | S0029 bit pattern + S0003 bit pattern |

Methods with no natural status confirmation (e.g. `set_dynamic_bands`, `set_clock`) accept `confirm:` but it is a no-op or raises `NotImplementedError`.

## Phase 4 — rsmp gem: Expanded status subscriptions and caching

- Extend `auto_subscribe_to_statuses` to also subscribe to S0001, S0007, S0011, S0015 (in addition to S0014)
- Extend `process_status_update` to cache: `@functional_position` (S0007 status), `@traffic_situation` (S0015 status), `@yellow_flash` (S0011 status)
- Add read-only accessors for all cached status values

## Phase 5 — rsmp gem: Tests

Expand `spec/rsmp/tlc/traffic_controller_proxy_spec.rb` with tests for:
- `wait_for_status` (subscribe → match → unsubscribe, timeout, ensure cleanup)
- `switch_*` methods (verifying both command and status wait)
- Security code handling (`security_code_for` returns correct value, raises on missing)

Run: `bundle exec rspec spec/rsmp/tlc/traffic_controller_proxy_spec.rb`

## Phase 6 — rsmp_validator: Security code config path

- Investigate `spec/support/config_normalizer.rb` and `config/gem_tlc.yaml` / secrets files
- Ensure `security_codes` appears in site settings at path proxy reads: `@site_settings['security_codes']` → `{ 2 => 'xxx' }`
- Likely fix: update `config_normalizer.rb` to merge `secrets.security_codes` into supervisor default settings, OR add `security_codes` key directly to site config YAML

## Phase 7 — rsmp_validator: Thin out `StatusHelpers`

- `wait_for_status` becomes a thin wrapper calling `@site.wait_for_status` passing validator-specific timeout defaults (`Validator.get_config('timeouts', 'command')`) and `Validator.get_config('main_component')`
- Keep: `require_security_codes`, `convert_status_list`, `wait_for_groups`, `read_cycle_times`, `read_current_plan`
- Keep context managers: `with_cycle_time_extended`, `with_clock_set`, `with_alarm_activated`
- Remove: `use_soc?` (moved to proxy), `verify_status` (deprecated)

## Phase 8 — rsmp_validator: Update all TLC spec files

Replace helper calls with direct `@site.method_name(...)` calls per spec file:

| Spec file | Old helper | New proxy call |
|-----------|-----------|----------------|
| `modes_spec.rb` | `switch_yellow_flash` | `@site.set_functional_position('YellowFlash', confirm!: {...})` |
| `modes_spec.rb` | `switch_dark_mode` | `@site.set_functional_position('Dark', confirm!: {...})` |
| `modes_spec.rb` | `switch_normal_control` | `@site.set_functional_position('NormalControl', confirm!: {...})` |
| `modes_spec.rb` | `set_functional_position` | `@site.set_functional_position` |
| `modes_spec.rb` | `apply_fixed_time` / `switch_fixed_time` | `@site.set_fixed_time` / `@site.set_fixed_time(..., confirm!: {...})` |
| `signal_plans_spec.rb` | `apply_plan`, `switch_plan` | `@site.set_timeplan` / `@site.set_timeplan(..., confirm!: {...})` |
| `traffic_situations_spec.rb` | `apply_traffic_situation` / `switch_traffic_situation` | `@site.set_traffic_situation` / `@site.set_traffic_situation(..., confirm!: {...})` |
| `emergency_routes_spec.rb` | `enable_emergency_route` / `disable_emergency_route` | `@site.set_emergency_route(active: true/false)` |
| `io_spec.rb` | `force_input`, `force_output`, `set_input` | `@site.force_input`, `@site.force_output`, `@site.set_input` |
| `detector_logics_spec.rb` | `force_detector_logic`, `apply_trigger_level` | `@site.force_detector_logic`, `@site.set_trigger_level` |
| `signal_groups_spec.rb` | `set_signal_start` / `set_signal_stop` | `@site.order_signal_start` / `@site.order_signal_stop` |
| `clock_spec.rb` | `apply_clock`, `reset_clock` | `@site.set_clock` |
| `alarm_spec.rb` | individual command helpers | updated; `with_alarm_activated` stays in validator |
| `signal_plans_spec.rb` | `set_dynamic_bands`, `set_offset`, `set_cycle_time`, `apply_week_table`, `apply_day_table` | `@site.set_*` equivalents |

Remove `prepare(task, site)` calls where `@task` is no longer needed after migration. Keep where context managers still require it (`with_alarm_activated`, `verify_startup_sequence`).

## Phase 9 — rsmp_validator: Remove/deprecate `CommandHelpers` methods now in proxy

Remove methods fully covered by proxy:
`apply_plan`, `set_functional_position`, `apply_traffic_situation`, `unset_traffic_situation`, `switch_traffic_situation`, `enable_emergency_route`, `disable_emergency_route`, `set_input`, `force_detector_logic`, `switch_plan`, `switch_yellow_flash`, `switch_dark_mode`, `apply_series_of_inputs`, `set_dynamic_bands`, `set_offset`, `apply_week_table`, `apply_day_table`, `set_cycle_time`, `force_input`, `force_output`, `apply_trigger_level`, `apply_timeout_for_dynamic_bands`, `apply_security_code`, `apply_clock`, `reset_clock`, `switch_normal_control`, `switch_fixed_time`, `apply_fixed_time`, `set_signal_start`, `set_signal_stop`

Note: `switch_*` wrapper methods in validator are replaced by `set_*(confirm!: {...})` calls directly — no separate proxy methods needed.

Keep:
- `require_security_codes` — RSpec skip helper, validator-specific
- `build_command_list` — still useful for edge-case raw commands (e.g. `wrong_security_code`)
- `send_command_and_confirm` — low-level fallback
- `with_alarm_activated`, `suspend_alarm`, `resume_alarm` — complex RSpec context managers
- `with_clock_set`, `with_cycle_time_extended` — context managers (deferred to later)
- `force_input_and_confirm` — composite helper; can stay until fully replaced
- `stop_sending_watchdogs`, `wrong_security_code` — test utilities
- `verify_startup_sequence` and related private helpers — complex, stays for now
- `switch_input` — composite helper; stays until migrated
- `wait_normal_control` — thin wrapper; can delegate to proxy `switch_normal_control` wait logic

---

## Relevant Files

### rsmp gem
- `lib/rsmp/tlc/traffic_controller_proxy.rb` — all new proxy methods go here
- `spec/rsmp/tlc/traffic_controller_proxy_spec.rb` — tests to expand
- `lib/rsmp/node/supervisor/supervisor.rb` — no changes needed (`build_proxy` already correct)
- `lib/rsmp/proxy/site/site_proxy.rb` — base class (provides `send_command`, `subscribe_to_status`, `request_status`)

### rsmp_validator
- `spec/support/command_helpers.rb` — thin out
- `spec/support/status_helpers.rb` — `wait_for_status` becomes wrapper
- `spec/support/config_normalizer.rb` — may need security code merge
- `config/gem_tlc.yaml` — may need `security_codes` at site level
- `config/gem_tlc_secrets.yaml` — current secrets location
- `spec/site/tlc/modes_spec.rb`
- `spec/site/tlc/signal_plans_spec.rb`
- `spec/site/tlc/traffic_situations_spec.rb`
- `spec/site/tlc/emergency_routes_spec.rb`
- `spec/site/tlc/io_spec.rb`
- `spec/site/tlc/detector_logics_spec.rb`
- `spec/site/tlc/signal_groups_spec.rb`
- `spec/site/tlc/clock_spec.rb`
- `spec/site/tlc/alarm_spec.rb`

---

## Verification

1. `cd rsmp && bundle exec rspec` — all existing proxy tests pass throughout all phases
2. `cd rsmp && bundle exec rspec spec/rsmp/tlc/traffic_controller_proxy_spec.rb` — new proxy tests pass (after Phase 5)
3. `cd rsmp_validator && AUTO_SITE_CONFIG=config/simulator/tlc.yaml bundle exec rspec spec/site/tlc --format documentation` — all TLC tests pass (after Phase 8)
4. Confirm `@site.current_plan` and `@site.switch_plan` work correctly in `signal_plans_spec`

---

## Scope Boundaries

**Included**: All M-codes listed above, status caching for key statuses, `wait_for_status` in proxy, validator spec updates, security code path fix

**Excluded**: `SignalGroupSequenceHelper` (no change needed), supervisor tests, non-TLC spec files

**Deferred**: Context managers (`with_cycle_time_extended`, `with_clock_set`, `with_alarm_activated`) — keep in validator; move later. `verify_startup_sequence` — stays in validator.

---

## Key Risk: Security Code Config Path

The security code config path is the most likely blocker. The proxy reads `@site_settings['security_codes']` but the validator currently stores them at `secrets.security_codes`. This must be verified and fixed in Phase 6 before Phase 8 can succeed.

Possible fix options:
1. Update `config_normalizer.rb` to merge `secrets.security_codes` into the site settings hash passed to the proxy
2. Pass security codes explicitly in the supervisor YAML under `default.security_codes`
3. Both — normalizer populates the YAML path, proxy reads from there
