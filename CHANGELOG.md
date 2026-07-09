## [Unreleased]

- Feature: `@supports (condition) { ... }` now preserves its condition and the rules it wraps through parse -> serialize, in both backends - previously the condition was discarded entirely and the wrapped rules were silently flattened into the surrounding document with no trace of ever being conditional.
- Feature: `@container name (condition) { ... }` (container queries) now preserves its name, condition, and wrapped rules the same way - handles named, anonymous, and name-only forms, and nests correctly with `@media`/`@supports`/itself.
- Feature: `@layer` (cascade layers) now preserves its name and wrapped rules, both in block form (`@layer name { ... }`, including anonymous and dotted/nested names like `framework.layout`) and statement form (`@layer a, b;`, which declares layer order with no wrapped rules at all - previously silently corrupted parsing of whatever rule came right after it).
- Fix: `@media`/`@supports`/`@container`/`@scope`/`@layer` with no whitespace before a following `(` (e.g. minified `@supports(display:grid){...}`) no longer misparses the at-rule name, which silently corrupted the rest of the block. Present in both backends since `@media`/`@supports` shipped.
- Feature: `@namespace` (default and prefixed, e.g. `@namespace svg url(http://www.w3.org/2000/svg);`) is now preserved through parse -> serialize, in both backends - previously it wasn't modelled at all. Namespaced selectors (`ns|E`, `*|E`, `|E`, and the attribute-selector equivalents) already parsed as opaque text, but their specificity was miscounted - a namespace prefix was counted as its own type selector instead of contributing nothing, e.g. `svg|rect` computed as specificity 2 instead of 1. Both are fixed now.

## [0.4.0] - 2026-07-08

- Fix: `Declarations.new(some_string)` (standalone CSS declaration-block parsing) now works under the pure Ruby backend (`CATARACT_PURE=1`) - previously raised `NoMethodError`.
- Fix: a compound `@media` list (e.g. `@media screen, print { ... }`) no longer silently collapses to just its first member when the document also contains CSS nesting elsewhere.
- Fix: `to_s`/`to_formatted_s` with a specific `media:` filter (anything but `:all`) could crash while grouping comma-separated selector lists (e.g. `h1, h2 { ... }`), if an unrelated rule elsewhere in the document was excluded by the filter. Present in both backends since at least 0.3.0.
- Fix: `Stylesheet#flatten` (non-destructive) could silently expand shorthand properties (e.g. `margin: 0`) on the *original* stylesheet as a side effect, under the pure Ruby backend. Present since at least 0.3.0; the C extension was unaffected.
- Breaking (minor): removed `Cataract.merge` (a long-deprecated alias for `.flatten`) and `Cataract.parse_media_types` (undocumented, no real callers) from the C extension's public surface. Use `Cataract.flatten`/`Stylesheet#flatten` instead of `.merge`.
- Internal: `Cataract`'s own directly-callable methods are now just `.flatten` and `.parse_css`. Previously `Cataract` also exposed `calculate_specificity`, `expand_shorthand`, `parse_declarations`, `stylesheet_to_s`, `stylesheet_to_formatted_s`, and `_parse_css` directly - undocumented implementation leakage, not intended for direct use. The documented ways to reach this functionality (`Rule#specificity`, `Rule#expanded_declarations`, `Declarations.new(some_string)`, `Stylesheet#to_s`/`#to_formatted_s`) are unchanged. The native C extension and pure Ruby backend also now live under `Cataract::Backends::Native` / `Cataract::Backends::Pure`, resolved once per process and held per-`Stylesheet` - this lets both backends coexist in the same process (e.g. for direct comparison). Existing callers relying only on the documented public API should notice nothing.

## [0.3.0] - 2026-07-06

- Security/Breaking: `Stylesheet#load_uri` and `#load_file` now reject `file://` paths under `/etc/`, `/proc/`, `/sys/`, and `/dev/` by default (override with `dangerous_path_prefixes: []`). Previously these methods used a separate, unvalidated fetch implementation; they now reuse `ImportResolver` (the same validation and fetching `@import` resolution already uses), which also fixes `load_uri` not following HTTP redirects.
- Fix: rules nested 3+ levels deep, or nested inside a top-level `@media`/`@supports`/`@container`/`@scope` block, could serialize incorrectly (silently flattened, or printed as an unrelated top-level rule) in the pure Ruby backend.
- Fix: a bare type selector nested without `&` (invalid CSS nesting) no longer corrupts serialized output with unbalanced braces, in both the C and pure Ruby parsers.
- Fix: `@keyframes` parsing no longer pollutes the outer rule list with its own inner selectors.
- Fix: at-rules (`@keyframes`, `@font-face`, etc.) nested inside `@media` blocks now correctly keep their media context across parsing, merging (`add_block`, `concat`/`+`), `@import` resolution, and serialization - previously this could be lost, misattributed, or (combined with CSS nesting) raise `NoMethodError` in the pure Ruby serializer.
- Fix: `remove_rules!` and the `-` operator no longer desync media query ids from the rules that reference them.
- Fix: resolving `@import`s no longer leaves duplicate/colliding rule ids.
- Fix: a plain `@import "file.css";` (no media qualifier) no longer loses that file's own `@media` rules.
- Fix: `Stylesheet#concat`/`+` now merges the other stylesheet's media queries and selector-list groupings too - previously this silently dropped `h1, h2`-style grouping and corrupted media attribution.
- Fix: `@import` media queries with a type keyword (e.g. `"screen and (min-width: 500px)"`) no longer keep a stray `"and"` in the parsed conditions.
- Fix: `to_s`/`to_formatted_s` media filtering is now consistent between the two - both include base (non-media) rules when filtering to a specific media type; previously `to_s` excluded them while `to_formatted_s` included them.
- Fix: values containing `url(...;...)` no longer lose everything after the first semicolon when the rule also uses CSS nesting.
- Fix: `!important` now parses correctly with whitespace between `!` and `important`, per the CSS grammar.
- Fix: expanding `border`, `border-{top,right,bottom,left}`, `font`, `background`, and `list-style` shorthands (used when comparing rules for equality) no longer silently drops `!important`.
- Fix: `Declarations`/`Stylesheet` `#dup`/`#clone` now produce fully independent copies; previously mutating a copy could mutate the original.
- Performance: CSS selector specificity calculation is ~30% faster (no longer re-allocates an internal lookup array on every call).
- Performance: native (C extension) CSS flattening is ~1-5% faster (fewer string allocations when recreating shorthand properties).

## [0.2.5 - 2025-11-25]

- Feature: Parse error detection with `raise_parse_errors` option - validates CSS structure and raises `ParseError` exceptions for malformed input with line/column tracking
- Feature: Granular error control - enable specific checks (empty values, malformed declarations, invalid selectors, invalid selector syntax, malformed at-rules, unclosed blocks)
- Feature: Type safety validation for C extension - `Stylesheet.parse` and `Stylesheet.new` now validate argument types and raise clear `TypeError` instead of segfaulting
- Feature: Selector syntax validation using whitelist approach - catches invalid characters and sequences like `..class`, `##id`, `???`
- Fix: `add_block` with multiple `@import` statements now correctly tracks media type for each import instead of reusing the first import's media context
- Performance: Parse error checking adds minimal overhead (effectively zero for C/Pure Ruby, ~5% for Pure Ruby with YJIT)
- Testing: Fuzzer corpus enhanced with invalid CSS patterns for crash testing

## [0.2.4 - 2025-11-23]
- MediaQuery first-class objects: Refactored media queries from simple symbols to proper structs with id, type, and conditions, enabling accurate
serialization and proper handling of complex queries like @media screen and (min-width: 768px)
- Fixed import resolution: Import statements now properly merge selector lists and media query lists from imported stylesheets with correct ID offsetting,
 preventing data loss
- Sequential rule ID invariant: Parser now ensures rules[i].id == i via placeholder strategy, enabling O(1) array access instead of O(N) lookups during
serialization
- Improved nested media handling: Nested media queries in imports now combine correctly (e.g., @import "file.css" screen where file contains @media
  (min-width: 768px))

## [0.2.3 - 2025-11-18]
- Pure Parser: Bugs with url()

## [0.2.2 - 2025-11-18]

- Feature: Selector list tracking - parser preserves comma-separated selector groupings (e.g., `h1, h2, h3`) through parse/flatten/serialize cycle
- Feature: Intelligent selector list serialization - automatically detects divergence during cascade and groups only matching rules
- Feature: Formatted CSS output with configurable line wrapping (`to_s(formatted: true, max_line_length: 80)`)
- Feature: Custom property (CSS variable) support - `Stylesheet#custom_properties` returns custom properties organized by media context
- Fix: Custom properties now preserve case-sensitivity per CSS spec (`--Color` vs `--color` are distinct)
- Fix: Custom properties support UTF-8 encoding for Unicode characters
- Fix: Property matching now supports prefix matching for vendor-prefixed properties
- Performance: Flatten operation optimized with manual iteration for selector list grouping

## [0.2.1] - 2025-11-14

- Fix serializer bug related to media queries

## [0.2.0] - 2025-11-14

- Major: CSS `@import` resolution refactored from string-concatenation to parsed-object architecture with proper charset handling, media query combining,
and circular import detection
- Major: Terminology change: all `merge` methods renamed to `flatten` to better represent CSS cascade behavior (old names deprecated with warnings)
- Major: Rule equality now considers shorthand/longhand property equivalence (e.g., `margin: 10px` equals `margin-top: 10px; margin-right: 10px; ...`)
- Performance: Flatten operation optimized with array-based property storage, pre-allocated frozen strings, and lazy specificity calculation
- Feature: New Stylesheet collection methods (`+`, `-`, `|`, `concat`, `take`, `take_while`) with cascade rules applied
- Feature: Added source order tracking for proper CSS cascade resolution

## [0.1.4] - 2025-11-12
- Major: Pure Ruby implementation added (#12)
- Fix: Media query serialization bugs - parentheses now preserved per CSS spec (min-width: 768px), fixed media query ordering
- Fix: CSS merge declaration ordering made consistent between C and pure Ruby implementations
- Fix: Shorthand property recreation (margin, padding, border, font, background, list-style) ordering
- Fix: Rule equality comparisons (Rule#==, AtRule#==)

## [0.1.3] - 2025-11-11
- Fix: Proper handling of at-rules (@keyframes, @font-face, etc.) during CSS merge operations

## [0.1.2] - 2025-11-11

- Fix segfault in merge

## [0.1.1] - 2025-11-09

- Fix bugs with Stylesheet#merge resulting in wrong results (#11)

## [0.1.0] - 2025-11-09
