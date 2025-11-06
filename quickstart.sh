#!/bin/bash

# Quick start script - runs setup and verifies installation

echo "🚀 NewRelic AI Agent - Quick Start"
echo "=" * 60

# Step 1: Make setup executable and run it
echo ""
echo "📦 Step 1: Running setup..."
chmod +x setup.sh
./setup.sh

# Step 2: Verify structure
echo ""
echo "📁 Step 2: Verifying structure..."
if [ -d "lib" ] && [ -f "lib/tools.rb" ] && [ -f "lib/context_loader.rb" ]; then
    echo "   ✅ lib directory created"
    echo "   ✅ lib/tools.rb exists"
    echo "   ✅ lib/context_loader.rb exists"
else
    echo "   ❌ Setup failed - lib directory or files missing"
    exit 1
fi

# Step 3: Install dependencies
echo ""
echo "📚 Step 3: Installing Ruby dependencies..."
if command -v bundle &> /dev/null; then
    bundle install
    echo "   ✅ Dependencies installed"
else
    echo "   ⚠️  Bundler not found - run 'gem install bundler' first"
fi

# Step 4: Show next steps
echo ""
echo "=" * 60
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. 📝 Edit claude.md:"
echo "   - Open: https://dev.azure.com/mindbody/mb2/_git/aws-arcus-services"
echo "   - Copy the 'Configuration for NewRelic Dashboards' section"
echo "   - Paste it into claude.md where marked"
echo ""
echo "2. 🔑 Setup GitHub Secrets (if not already done):"
echo "   - CLAUDE_API_KEY (from https://console.anthropic.com)"
echo "   - NEW_RELIC_API_KEY (from NewRelic)"
echo ""
echo "3. 🚢 Push to GitHub:"
echo "   git add ."
echo "   git commit -m 'Add NewRelic AI Agent'"
echo "   git push origin main"
echo ""
echo "4. 📦 Use in any microservice:"
echo "   Copy example-workflow.yml to:"
echo "   .github/workflows/newrelic-ai.yml"
echo ""
echo "5. 🧪 Test locally (optional):"
echo "   export CLAUDE_API_KEY='your-key'"
echo "   export NEWRELIC_API_KEY='your-key'"
echo "   export GITHUB_TOKEN='your-token'"
echo "   export GITHUB_REPOSITORY='org/repo'"
echo "   export PR_NUMBER='123'"
echo "   ruby test_local.rb"
echo ""
echo "📚 See README.md for full documentation"
