#!/bin/bash
set -e

echo "🚀 Setting up Helm Chart Factory..."

# Check for required tools
command -v python3 >/dev/null 2>&1 || { echo "❌ python3 is required but not installed. Aborting." >&2; exit 1; }
command -v uv >/dev/null 2>&1 || { echo "❌ uv is required but not installed. Install from https://github.com/astral-sh/uv" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "⚠️  helm is not installed. Chart validation will be skipped." >&2; }

# Install Python dependencies
echo "📦 Installing chart-generator dependencies..."
cd chart-generator
uv pip install -r requirements.txt
cd ..

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Create a service configuration.yml file"
echo "  2. Generate a Helm chart:"
echo "     cd chart-generator && python main.py --config path/to/configuration.yml --library ../platform-library --output path/to/output"
echo ""
echo "Example:"
echo "  python main.py --config ./service-config.yml --library ../platform-library --output ./my-service-chart"

