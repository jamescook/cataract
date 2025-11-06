# Live Example

This is a live example of Cataract analyzing GitHub.com's CSS.

**{file:github_analysis.html View GitHub.com CSS Analysis Report}**

This analysis was generated using:

```bash
ruby examples/css_analyzer.rb https://github.com -o docs/github_analysis.html
```

The example demonstrates:
- **Real-world CSS parsing performance** - Analyzing 16,000+ rules from GitHub.com
- **Property usage statistics** - Top properties and their frequency
- **Color palette extraction** - All colors used across the site
- **Specificity analysis** - Distribution of selector complexity
- **!important usage patterns** - How often declarations are marked important

The analysis is regenerated each time documentation is built with `rake docs`.

## Running Your Own Analysis

You can analyze any website or CSS file:

```bash
# Analyze a website
ruby examples/css_analyzer.rb https://example.com

# Analyze a CSS file
ruby examples/css_analyzer.rb path/to/styles.css

# Save to HTML report
ruby examples/css_analyzer.rb https://example.com -o report.html
```
