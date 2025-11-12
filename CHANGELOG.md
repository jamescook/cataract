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
