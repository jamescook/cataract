# Performance Benchmarks

Comprehensive performance comparison between Cataract and css_parser gem.

## Test Environment

- **Ruby**: 3.4.5 (2025-07-16) with YJIT and PRISM
- **CPU**: Apple M1 Pro
- **Memory**: 32GB
- **OS**: macOS (darwin23)

## Premailer Integration

Drop-in replacement performance for Premailer email CSS inlining.

| Metric | css_parser | Cataract | Improvement |
|--------|------------|----------|-------------|
| **Speed** | 152.3 i/s (6.57 ms/op) | 2,668.1 i/s (374.80 μs/op) | **17.5x faster** |
| **Memory Allocations** | 38,215 objects | 833 objects | **97.8% reduction** |

### Key Takeaways
- Cataract provides **17.5x faster** CSS inlining for email templates
- Nearly **98% fewer** object allocations means less GC pressure
- Zero code changes required - just call `Cataract.mimic_CssParser!`

---

## CSS Parsing

Performance of parsing CSS into internal data structures.

### Small CSS (64 lines, 1KB)

| Parser | Speed | Time per operation |
|--------|-------|-------------------|
| css_parser | 6,349 i/s | 157.50 μs |
| **Cataract** | **68,482 i/s** | **14.60 μs** |
| **Speedup** | **10.8x faster** | |

### Medium CSS with @media (139 lines, 1.7KB)

| Parser | Speed | Time per operation |
|--------|-------|-------------------|
| css_parser | 3,525 i/s | 283.67 μs |
| **Cataract** | **44,578 i/s** | **22.43 μs** |
| **Speedup** | **12.6x faster** | |

---

## CSS Serialization (to_s)

Performance of converting parsed CSS back to string format.

### Full Serialization (Bootstrap CSS - 196KB)

| Parser | Speed | Time per operation |
|--------|-------|-------------------|
| css_parser | 34.7 i/s | 28.81 ms |
| **Cataract** | **671.0 i/s** | **1.49 ms** |
| **Speedup** | **19.3x faster** | |

### Media Type Filtering (print only)

| Parser | Speed | Time per operation |
|--------|-------|-------------------|
| css_parser | 4,166 i/s | 240.04 μs |
| **Cataract** | **51,847 i/s** | **19.29 μs** |
| **Speedup** | **12.4x faster** | |

---

## Specificity Calculation

Performance of calculating CSS selector specificity values.

### Simple Selectors

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `div` | 1.24M i/s | 39.66M i/s | **32.0x** |
| `.class` | 939K i/s | 38.62M i/s | **41.1x** |
| `#id` | 1.28M i/s | 40.64M i/s | **31.8x** |

### Compound Selectors

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `div.container` | 674K i/s | 33.04M i/s | **49.0x** |
| `div#main` | 875K i/s | 35.32M i/s | **40.4x** |
| `div.container#main` | 567K i/s | 29.32M i/s | **51.7x** |

### Combinators

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `div p` | 1.09M i/s | 36.24M i/s | **33.2x** |
| `div > p` | 1.07M i/s | 34.28M i/s | **32.1x** |
| `h1 + p` | 1.08M i/s | 34.74M i/s | **32.2x** |
| `div.container > p.intro` | 417K i/s | 25.80M i/s | **61.9x** |

### Pseudo-classes & Pseudo-elements

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `a:hover` | 715K i/s | 31.33M i/s | **43.8x** |
| `p::before` | 630K i/s | 33.39M i/s | **53.0x** |
| `li:first-child` | 447K i/s | 29.56M i/s | **66.1x** |
| `p:first-child::before` | 314K i/s | 25.62M i/s | **81.5x** |

### :not() Pseudo-class

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `#s12:not(foo)` | 640K i/s | 15.05M i/s | **23.5x** |
| `div:not(.active)` | 413K i/s | 13.53M i/s | **32.8x** |
| `.button:not([disabled])` | 370K i/s | 11.41M i/s | **30.8x** |

**Note**: css_parser has a bug where it doesn't correctly parse `:not()` content, affecting specificity accuracy.

### Complex Real-world Selectors

| Selector | css_parser | Cataract | Speedup |
|----------|------------|----------|---------|
| `ul#nav li.active a:hover` | 352K i/s | 21.74M i/s | **61.7x** |
| `div.wrapper > article#main > section.content > p:first-child` | 261K i/s | 15.58M i/s | **59.7x** |
| `[data-theme='dark'] body.admin #dashboard .widget a[href^='http']::before` | 204K i/s | 14.20M i/s | **69.6x** |

---

## CSS Merging

Performance of merging multiple CSS rule sets with the same selector.

| Test Case | css_parser | Cataract | Speedup |
|-----------|------------|----------|---------|
| Simple properties | 40.1K i/s | 118.1K i/s | **2.9x** |
| Cascade with specificity | 45.6K i/s | 195.9K i/s | **4.3x** |
| Important declarations | 44.5K i/s | 198.1K i/s | **4.5x** |
| Shorthand expansion | 36.8K i/s | 113.9K i/s | **3.1x** |
| Complex merging | 16.4K i/s | 40.0K i/s | **2.4x** |

### What's Being Tested
- Specificity-based CSS cascade (ID > class > element)
- `!important` declaration handling
- Shorthand property expansion (e.g., `margin` → `margin-top`, `margin-right`, etc.)
- Shorthand property creation from longhand properties

---

## YJIT Impact

Impact of Ruby's YJIT JIT compiler on Ruby-side operations. The C extension performance is the same regardless of YJIT.

### Operations Per Second

| Operation | Without YJIT | With YJIT | YJIT Improvement |
|-----------|--------------|-----------|------------------|
| Property access (get/set) | 226.4K i/s | 307.1K i/s | **1.36x** (36% faster) |
| Declaration merging | 197.7K i/s | 314.4K i/s | **1.59x** (59% faster) |
| to_s generation | 239.3K i/s | 366.1K i/s | **1.53x** (53% faster) |
| Parse + iterate | 89.7K i/s | 104.9K i/s | **1.17x** (17% faster) |

### Key Takeaways
- YJIT provides **17-59% performance boost** for Ruby-side operations
- Greatest impact on declaration merging (**59% faster**)
- Parse + iterate benefits least (only **17%**) since most work is in C
- Recommended: Enable YJIT in production (`--yjit` flag or `RUBY_YJIT_ENABLE=1`)

---

## Summary

### Performance Highlights

| Category | Best Speedup | Typical Range |
|----------|--------------|---------------|
| **Premailer Integration** | 17.5x | N/A |
| **Parsing** | 12.6x | 10-13x |
| **Serialization** | 19.3x | 12-19x |
| **Specificity** | 81.5x | 23-82x |
| **Merging** | 4.5x | 2.4-4.5x |

### Why Is Cataract Faster?

1. **C Extension**: Critical paths (parsing, specificity, merging, serialization) implemented in C
2. **Efficient Data Structures**: Rules grouped by media query for O(1) lookups
3. **Memory Efficient**: Pre-allocated string buffers, minimal Ruby object allocations
4. **Optimized Algorithms**: Purpose-built CSS specificity calculator, no regex-heavy parsing

### When to Use Cataract

- ✅ **Email inlining** (Premailer): 17.5x faster, drop-in replacement
- ✅ **Large CSS files**: 10-20x faster parsing and serialization
- ✅ **Specificity calculations**: 23-82x faster, especially for complex selectors
- ✅ **High-volume processing**: 98% fewer allocations = less GC pressure
- ✅ **Production applications**: Battle-tested on Bootstrap CSS and real-world stylesheets

---

## Running Benchmarks

```bash
# All benchmarks
rake benchmark 2>&1 | tee benchmark_output.txt

# Individual benchmarks
rake benchmark:parsing
rake benchmark:serialization
rake benchmark:specificity
rake benchmark:merging
rake benchmark:premailer
rake benchmark:yjit
```

## Notes

- All benchmarks use benchmark-ips with 3s warmup and 5-10s measurement periods
- Measurements are median i/s (iterations per second) with standard deviation
- css_parser gem must be installed for comparison benchmarks
- Premailer benchmark requires premailer gem
