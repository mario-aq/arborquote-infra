#!/bin/bash

# Test runner script for ArborQuote Lambda functions
# Usage: ./run_tests.sh [options]

set -e

cd "$(dirname "$0")"

echo "======================================"
echo "  ArborQuote Lambda Tests"
echo "======================================"
echo ""

# Initialize rbenv if present
if command -v rbenv &> /dev/null; then
    eval "$(rbenv init - bash)"
fi

# Check if bundler is installed
if ! command -v bundle &> /dev/null; then
    echo "❌ Bundler not found. Installing..."
    gem install bundler
fi

# Install dependencies if needed
if [ ! -d "vendor/bundle" ]; then
    echo "📦 Installing Ruby dependencies..."
    bundle install --path vendor/bundle
    echo ""
fi

# Run tests
echo "🧪 Running tests..."
echo ""

bundle exec rspec "$@"

echo ""
echo "✅ Tests complete!"

