## [ Unreleased ]

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
