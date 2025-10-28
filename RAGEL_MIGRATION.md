# Ragel to Pure C Migration

## Why We Switched

Started with Ragel as an experiment for the CSS parser, but quickly moved to hand-written pure C in October 2024.

### Performance

Benchmarks showed the pure C implementation was **2.08x faster** than Ragel's default style (T0):

```
Parsing bootstrap.css (10,000 iterations)
Ragel (T0):  1.234s
Pure C:      0.593s  (2.08x faster)
```

While Ragel's F0/F1 styles were faster than T0, they produced significantly larger binaries and had longer compile times.

### Compilation Speed

- **Ragel**: 2-3 seconds to generate C code, then compile
- **Pure C**: Immediate compilation, no code generation step

Some Ragel styles (G0/G1/G2) never finished compiling - waited 10+ minutes before giving up.

### Ragel Complexity Issues

Hit walls with non-determinism and state machine complexity:
- Adding `@charset` support caused compile times to explode
- Issues with entering/leaving characters in complex patterns
- State machine became too complex for Ragel to optimize efficiently

### Binary Size

Hand-written C produces smaller binaries compared to Ragel's generated code, especially the faster F0/F1 styles.

### Maintainability

- Pure C is more familiar to contributors (no Ragel DSL to learn)
- Easier to debug (no generated code indirection)
- Standard C tooling works out of the box (debuggers, profilers, linters)
- No build-time Ragel dependency for gem users

### Build Simplicity

Removing Ragel eliminated:
- Build-time dependency on Ragel binary
- Separate code generation step in CI
- Platform-specific Ragel installation issues
- Complexity in the build toolchain

## Trade-offs

Pure C is more verbose than Ragel's DSL, but the performance gains and simpler build process made it an easy choice.

## Details

- Swapped in October 2024
- Files: `css_parser.c`, `specificity.c`, `value_splitter.c`
- API unchanged, all tests pass
