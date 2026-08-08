# logtree function list

Full inventory of functions in `R/`, params, and source file. Exported fns marked `[export]`.

## Step lifecycle (R/step.R)

| Function | Params |
|---|---|
| `log_step` `[export]` | `msg, glyph = NULL, parent = NULL, group = NULL, close = FALSE, key = NULL` |
| `log_open` `[export]` | `msg, glyph = NULL, parent = NULL, group = NULL, close = FALSE, key = NULL` |
| `log_close` `[export]` | `id = NULL, status = NULL` |
| `current_parent_id` | *(none)* |
| `current_depth` | *(none)* |
| `current_path` | *(none)* |
| `parse_group` | `group` |
| `settle_groups` | `name = NULL, value = NULL` |
| `open_or_reuse_group` | `name, value` |
| `elevate_group_status` | `id, status` |
| `reconcile_open_step` | `key, srcref` |
| `src_location` | `call` |
| `push_step` | `label, glyph = NULL, group = NULL, parent = NULL, key = NULL, srcref = NULL, trace = NULL` |
| `find_stack_entry` | `id` |
| `set_stack_entry_status` | `id, status` |
| `resolved_status` | `status` |
| `close_step` | `id, silent = FALSE` |
| `close_current_section_silent` | *(none)* |
| `finalize_step` | `id, sentinel` |
| `tree_col_width` | `theme = the$theme` |
| `wrap_message` | `msg, width` |
| `hard_wrap` | `x, width` |
| `timestamp_format` | `theme = the$theme` |
| `fit_to_width` | `x, w` |
| `timestamp_column` | `stamp, theme = the$theme, color = TRUE` |
| `compose_line` | `head, msg, cols, cont, theme = the$theme, stamp = NULL, color = TRUE` |
| `rails` | `n, theme = the$theme, color = TRUE` |
| `glyph_gutter` | `theme = the$theme` |
| `compose_flat_line` | `glyph, msg, theme = the$theme, stamp = NULL, color = TRUE` |
| `rail_unit` | `theme = the$theme, color = TRUE` |
| `connector_str` | `key, theme = the$theme, color = TRUE` |
| `own_connector_str` | `key, theme = the$theme, color = TRUE` |
| `own_connector_width` | `key, theme = the$theme` |
| `own_rail` | `key, theme = the$theme, color = TRUE` |
| `glyph_rail` | `theme = the$theme, color = TRUE, w = glyph_gutter(theme)` |
| `pad_custom_glyph` | `glyph, theme = the$theme` |
| `format_open` | `entry, theme = the$theme, color = TRUE, stamp = NULL` |
| `close_text_template` | `status, theme = the$theme` |
| `expand_close_text` | `template, entry, elapsed` |
| `format_elapsed_field` | `seconds, theme = the$theme, color = TRUE, gate = TRUE` |
| `trace_value` | `key, trace` |
| `expand_trace_text` | `template, trace, styles = NULL, link = FALSE` |
| `trace_link` | `text, trace` |
| `trace_styles` | `theme = the$theme` |
| `format_trace_field` | `trace, kind, status = NULL, theme = the$theme, color = TRUE` |
| `render_trace_text` | `trace, theme = the$theme, color = TRUE` |
| `format_trace_digest` | `trace, status = NULL, theme = the$theme, color = TRUE` |
| `with_trace` | `msg, trace_text` |
| `close_message` | `entry, status, theme = the$theme, color = TRUE` |
| `format_close` | `entry, theme = the$theme, color = TRUE, stamp = NULL` |
| `format_leaf` | `status, msg, depth, theme = the$theme, color = TRUE, corner = FALSE, trace = NULL, stamp = NULL` |
| `format_group_header` | `entry, theme = the$theme, color = TRUE, stamp = NULL` |

## Call-site capture (R/trace.R)

| Function | Params |
|---|---|
| `resolve_trace_show` | `theme = the$theme` |
| `trace_enabled` | `theme = the$theme` |
| `src_parts` | `call` |
| `display_path` | `abs` |
| `call_fn_name` | `call` |
| `capture_trace` | `call, up = 1L` |
| `trace_from_call` | `call` |

## Leaf logging (R/leaves.R)

| Function | Params |
|---|---|
| `log_debug` `[export]` | `msg, close = FALSE, summary = NA` |
| `log_info` `[export]` | `msg, close = FALSE, summary = NA` |
| `log_success` `[export]` | `msg, close = FALSE, summary = NA` |
| `log_warn` `[export]` | `msg, close = FALSE, summary = NA` |
| `log_error` `[export]` | `msg, close = FALSE, summary = NA` |
| `status_severity` | `status` |
| `nearest_open_step` | *(none)* |
| `elevate_current_step` | `new_status` |
| `resolve_threshold` | `threshold` |
| `sink_threshold_rank` | `threshold` |
| `sink_admits_leaf` | `status, threshold` |
| `any_sink_admits` | `status` |
| `leaf_wanted` | `status, summary` |
| `emit_leaf` | `status, msg, close = FALSE, summary = NA, trace = NULL, capture = TRUE` |
| `log_condition_at` | `status, msg, call` |
| `log_error_at` | `msg, call` |

## Run wrapper (R/run.R)

| Function | Params |
|---|---|
| `with_logging` `[export]` | `expr, summary = TRUE, global = FALSE, warnings = FALSE` |
| `mark_open_steps` | `status` |
| `print_run_summary` | `status, elapsed` |
| `resolve_warnings` | `x` |
| `route_condition` | `status, cnd, restart, guard = FALSE` |
| `route_warning` | `cnd, guard = FALSE` |
| `route_message` | `cnd, guard = FALSE` |
| `global_error_action` | `cnd, summary` |
| `install_global_logging` | `summary, routes = character(0)` |

## State / clock (R/state.R)

| Function | Params |
|---|---|
| `logtree_mute` `[export]` | *(none)* |
| `logtree_unmute` `[export]` | *(none)* |
| `logtree_reset` `[export]` | *(none)* |
| `new_run_id` | *(none)* |
| `now` | *(none)* |
| `wall_clock` | *(none)* |
| `format_elapsed` | `seconds` |

## Theme (R/theme.R)

| Function | Params |
|---|---|
| `logtree_theme` `[export]` | `theme = NULL, overrides = list(), compact = FALSE, glyph_gap = NULL, connector_gap = NULL, wrap = NULL` |
| `logtree_threshold` `[export]` | `level = c("debug", "info", "warn", "error")` |
| `theme_preset` | `name` |
| `console_preset` | `name` |
| `resolve_compact` | `x` |
| `resolve_connector_gap` | `x` |
| `resolve_glyph_gap` | `x` |
| `resolve_wrap` | `x` |
| `apply_compact` | `level` |
| `apply_overrides` | `overrides` |
| `theme_field` | `slot, field, default, theme = the$theme` |
| `theme_slot_width` | `theme = the$theme` |
| `close_glyph_key` | `status, theme = the$theme` |
| `theme_col_gap` | `theme = the$theme` |
| `theme_glyph_gap` | `theme = the$theme` |
| `theme_connector_gap` | `theme = the$theme` |
| `glyph_pad` | `theme = the$theme` |
| `theme_wrap_width` | `theme = the$theme` |
| `colorize` | `text, color, enabled = TRUE` |
| `theme_glyph` | `key, theme = the$theme, color = TRUE` |
| `theme_connector` | `key, theme = the$theme, color = TRUE` |

## Run summary digest (R/summary.R)

| Function | Params |
|---|---|
| `logtree_summary` `[export]` | `filter = NULL, depth = NULL, gap = NULL, rule = NULL, trace = NULL` |
| `covers` | `anc, desc` |
| `summary_keeps` | `status, summary` |
| `record_summary` | `event` |
| `resolve_gap` | `gap, theme = the$theme` |
| `digest_theme` | `trace` |
| `resolve_rule` | `rule, theme = the$theme` |
| `format_crumb` | `nodes, plain_last = FALSE, theme = the$theme, color = TRUE` |
| `print_summary_header` | `header, gap, rule` |

## Appenders / sinks (R/appenders.R)

| Function | Params |
|---|---|
| `logtree_sink_file` `[export]` | `path, format = c("text", "json"), trace = NULL, timestamp = NULL, threshold = NULL` |
| `emit` | `event` |
| `console_sink` | `event` |
| `text_sink_theme` | `trace, timestamp = NULL` |
| `file_text_sink` | `path, trace = NULL, timestamp = NULL` |
| `resolve_sink_timestamp` | `x` |
| `esc_json_string` | `x` |
| `json_scalar` | `x` |
| `record_proto` | *(none)* |
| `event_record` | `event` |
| `to_json_line` | `record` |
| `file_json_sink` | `path` |

## Sink registry (R/sinks.R)

| Function | Params |
|---|---|
| `logtree_sink` `[export]` | `fn, threshold = NULL` |
| `logtree_sink_memory` `[export]` | `max = 1000, threshold = NULL` |
| `logtree_sink_memory_events` `[export]` | `id` |
| `logtree_sinks` `[export]` | *(none)* |
| `logtree_sink_remove` `[export]` | `id` |
| `new_sink_id` | *(none)* |
| `register_sink` | `fn, threshold = NULL, trace = FALSE, store = NULL` |
| `records_to_df` | `records` |

## logger integration (R/logger-integration.R)

| Function | Params |
|---|---|
| `layout_logtree` `[export]` | `level, msg, namespace = NA_character_, .logcall = sys.call(), .topcall = sys.call(-1), .topenv = parent.frame(), .timestamp = Sys.time()` |
| `logtree_logger` `[export]` | `namespace = "global", threshold = TRUE` |

## Package hook (R/zzz.R)

| Function | Params |
|---|---|
| `.onLoad` | `libname, pkgname` |

## Data objects (not functions, R/glyphs.R)

`glyphs_unicode`, `glyphs_ascii`, `glyphs_emoji`, `glyphs_minimal`, `glyphs_ci` — named lists
keyed by glyph/status, no params. `theme_presets` — the character vector of preset names
`logtree_theme()` matches against. `trace_colors` / `trace_format` and
`default_timestamp_format` are the shared defaults those presets are built from.

---

**Totals:** 23 exported fns, 120 internal fns, 1 pkg hook, 12 package-level data
objects (the 5 glyph presets among them).
