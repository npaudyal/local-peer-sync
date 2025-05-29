#!/bin/bash

# Build script for Local Peer Sync
set -e

echo "🚀 Building Local Peer Sync"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "rust-core/Cargo.toml" ]; then
    print_error "Must run from project root (local-peer-sync/)"
    exit 1
fi

# Build Rust core
print_status "Building Rust core library..."
cd rust-core

# Check and format code
print_status "Checking code format..."
cargo fmt --check || {
    print_warning "Code needs formatting, running cargo fmt..."
    cargo fmt
}

# Run clippy for linting
print_status "Running clippy..."
cargo clippy -- -D warnings

# Run tests
print_status "Running tests..."
cargo test

# Build for development
print_status "Building debug version..."
cargo build

# Build optimized release
print_status "Building release version..."
cargo build --release

print_success "Rust core build completed!"

# Return to project root
cd ..

print_success "All builds completed successfully! 🎉"
echo ""
echo "Next steps:"
echo "1. Run tests: cd rust-core && cargo test"
echo "2. Run example: cd rust-core && cargo run --example basic"
echo "3. Build for specific platform: see scripts/build-ios.sh"