# Libsorbet Crystal Examples

This directory contains Crystal examples and tests for the libsorbet C API.

## Structure

- `main.cr` - Main example demonstrating basic usage
- `spec/` - Comprehensive test suite
  - `sorbet_spec.cr` - Core test infrastructure
  - `basic_spec.cr` - Basic functionality tests
  - `require_resolution_spec.cr` - Require/import resolution tests
- `Taskfile.yml` - Task runner configuration
- `spec.sh` - Convenience script for running specs

## Getting Started

### Prerequisites

1. **Crystal** - Install from https://crystal-lang.org/install/
2. **Task** - Install with `brew install go-task/tap/go-task`
3. **Libsorbet** - Build the C library first (see `../lib/README.md`)

### Note About Running Tests

The test suite requires the libsorbet C library to be built and available in your library path. When you run the tests, you may see an error like:

```
ld: library 'sorbet' not found
```

This is expected if you haven't built the C library yet. To build it:

```bash
cd ../lib

# For macOS (native build)
task build:macos

# For Linux (Docker build)
task build:linux

# Install to system (optional)
task install:macos  # macOS
task install:linux  # Linux
```

Once built, the tests should run successfully. You can also test with the main example:

```bash
cd ../crystal
crystal build main.cr -L../dist/macos  # macOS
crystal build main.cr -L../dist/linux  # Linux
```

### Running Examples

```bash
# Run the main example
crystal run main.cr

# Build the main example
crystal build main.cr
```

### Running Tests

```bash
# Show available tasks
task --list

# Run all specs
task spec

# Run specific test groups
task spec-basic      # Basic functionality tests
task spec-require    # Require resolution tests

# Clean up test files
task clean

# Run everything
task all
```

## Development

### Adding New Tests

1. Create a new spec file in the `spec/` directory
2. Follow the existing pattern (see `basic_spec.cr`)
3. Add the spec to the `Taskfile.yml` if needed
4. Run with `crystal spec spec/your_new_spec.cr`

### Test Structure

```crystal
require "./sorbet_spec"

describe "YourFeature" do
  it "does something" do
    # Test code
  end

  it "handles edge cases" do
    # More test code
  end
end
```

### Cleanup

The test suite automatically cleans up temporary files, but you can manually clean with:

```bash
task clean
```

## Integration with CI

Add this to your CI configuration:

```yaml
- name: Run Crystal specs
  run: |
    cd crystal
    task spec
```

## License

Same as the main Sorbet project (see ../LICENSE)
