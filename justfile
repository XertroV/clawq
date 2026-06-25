# Build release-speed, extract debug symbols, strip binary, ship both
bi:
    ./scripts/build-install.sh

# Build the project (dev)
build:
    make build

# Quick test (skips Slow-tagged tests)
test:
    make test

# Run all tests
test-all:
    make test-all

# Format code
fmt:
    make fmt

# Check formatting
fmt-check:
    make fmt-check

# Run CLI help
run:
    make run
