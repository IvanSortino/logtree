# logtree function list

Full inventory of functions in `R/`, params, and source file. Exported fns marked `[export]`.

## Step lifecycle (R/step.R)

| Function | Params |
|---|---|
| `log_step` `[export]` | `msg, glyph = NULL, group = NULL, close = FALSE` |
| `log_open` `[export]` | `msg, glyph = NULL, parent = NULL, group = NULL, close = FALSE` |
| `log_close` `[export]` | `id = NULL, status = NULL` |
| `push_step` | `label, glyph = NULL, group = NULL, parent = NULL` |
| `close_step` | `id, silent = FALSE` |
| `close_current_section_silent` | *(none)* |
| `finalize_step` | `id, sentinel` |
| `find_stack_entry` | `id` |
| `set_stack_entry_status` | `id, status` |
| `resolved_status` | `status` |
| `current_parent_id` | *(none)* |
| `current_depth` | *(none)* |
| `parse_group` | `group` |
| `settle_groups` | `name = NULL, value = NULL` |
| `open_or_reuse_group` | `name, value` |
| `elevate_group_status` | `id, status` |
| `tree_col_width` | `theme = the$theme` |
| `rail_unit` | `theme = the$theme, color = TRUE` |
| `connector_str` | `key, theme = the$theme, color = TRUE` |
| `pad_custom_glyph` | `glyph, theme = the$theme` |
| `format_open` | `entry, theme = the$theme, color = TRUE` |
| `format_close` | `entry, theme = the$theme, color = TRUE` |
| `format_leaf` | `status, msg, depth, theme = the$theme, color = TRUE, corner = FALSE` |
| `format_group_header` | `entry, theme = the$theme, color = TRUE` |

## Leaf logging (R/leaves.R)

| Function | Params |
|---|---|
| `log_debug` `[export]` | `msg, close = FALSE` |
| `log_info` `[export]` | `msg, close = FALSE` |
| `log_success` `[export]` | `msg, close = FALSE` |
| `log_warn` `[export]` | `msg, close = FALSE` |
| `log_error` `[export]` | `msg, close = FALSE` |
| `status_severity` | `status` |
| `nearest_open_step` | *(none)* |
| `elevate_current_step` | `new_status` |
| `should_emit_leaf` | `status` |
| `emit_leaf` | `status, msg, close = FALSE` |

## Run wrapper (R/run.R)

| Function | Params |
|---|---|
| `with_logging` `[export]` | `expr, summary = TRUE` |
| `mark_open_steps` | `status` |
| `print_run_summary` | `status, elapsed` |

## State / clock (R/state.R)

| Function | Params |
|---|---|
| `logtree_reset` `[export]` | *(none)* |
| `now` | *(none)* |
| `format_elapsed` | `seconds` |

## Theme (R/theme.R)

| Function | Params |
|---|---|
| `logtree_theme` `[export]` | `theme = c("unicode", "ascii", "emoji"), overrides = list()` |
| `logtree_threshold` `[export]` | `level = c("debug", "info", "warn", "error")` |
| `theme_preset` | `name` |
| `theme_slot_width` | `theme = the$theme` |
| `colorize` | `text, color, enabled = TRUE` |
| `theme_glyph` | `key, theme = the$theme, color = TRUE` |
| `theme_connector` | `key, theme = the$theme, color = TRUE` |

## Appenders / sinks (R/appenders.R)

| Function | Params |
|---|---|
| `logtree_sink_file` `[export]` | `path, format = c("text", "json")` |
| `emit` | `event` |
| `console_sink` | `event` |
| `file_text_sink` | `path` |
| `file_json_sink` | `path` |
| `esc_json_string` | `x` |
| `json_scalar` | `x` |
| `to_json_line` | `event` |

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

`glyphs_unicode`, `glyphs_ascii`, `glyphs_emoji` — named lists keyed by glyph/status, no params.

---

**Totals:** 14 exported fns, 33 internal fns, 1 pkg hook, 3 data objects.
