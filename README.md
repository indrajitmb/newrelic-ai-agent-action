# NewRelic AI Agent Action

Automatically generate NewRelic observability configurations for your pull requests using AI.

## 🎯 What It Does

When you open a PR, this GitHub Action:
1. Analyzes your code changes
2. Determines what monitoring is needed
3. Generates NewRelic dashboards and alerts
4. Posts recommendations as a PR comment

**Works with:** Python, Ruby, Node.js, Go, Java - any language!

## 🚀 Quick Start

### Step 1: Setup This Repository

```bash
cd newrelic-ai-agent-action

# Run setup script to create lib directory and files
chmod +x setup.sh
./setup.sh

# Install dependencies
bundle install
```

### Step 2: Configure Context

Edit `claude.md` and add your platform's NewRelic configuration format:

1. Open: https://dev.azure.com/mindbody/mb2/_git/aws-arcus-services?path=%2FREADME.md
2. Copy the "Configuration for NewRelic Dashboards" section
3. Paste into `claude.md` where marked

### Step 3: Add to Any Microservice

In **any** of your service repositories (Python, Node, Go, Ruby, etc.), add this workflow file:

**`.github/workflows/newrelic-ai.yml`:**

```yaml
name: NewRelic AI Analysis
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Run NewRelic AI Agent
        uses: your-org/newrelic-ai-agent-action@main
        with:
          claude-api-key: ${{ secrets.CLAUDE_API_KEY }}
          newrelic-api-key: ${{ secrets.NEW_RELIC_API_KEY }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Step 4: Setup Secrets

In your GitHub organization or repository settings:

**Settings → Secrets and variables → Actions → New secret**

Add these secrets:
- `CLAUDE_API_KEY` - Get from https://console.anthropic.com/settings/keys
- `NEW_RELIC_API_KEY` - Get from NewRelic → API Keys → User key

## 📁 Repository Structure

```
newrelic-ai-agent-action/
├── action.yml              # GitHub Action definition
├── codepulse.rb                # Main agent orchestrator
├── Gemfile                 # Ruby dependencies
├── context.md              # Context for AI (edit this!)
├── lib/
│   ├── context_loader.rb   # Loads claude.md
│   └── tools.rb            # AI tools for GitHub/NewRelic
├── setup.sh                # Setup script
└── README.md               # This file
```

## 🎓 How It Works

### The AI Agent Loop

```
PR Created
  ↓
Agent analyzes diff
  ↓
Decides what tools to use
  ↓
Executes tools (fetch code, query NewRelic, etc.)
  ↓
Generates recommendations
  ↓
Posts as PR comment
```

### Available Tools

The AI agent can use these tools autonomously:

1. **`get_pr_diff`** - Fetch code changes
2. **`analyze_file`** - Read specific files
3. **`query_newrelic`** - Check existing monitoring
4. **`check_existing_infrastructure`** - Read infrastructure.yml
5. **`create_temp_dashboard_files`** - Generate temp monitoring
6. **`suggest_permanent_config`** - Generate permanent config

## 📊 Example Output

The agent posts a comment on your PR like this:

```markdown
🤖 NewRelic AI Agent - Observability Analysis

## 📊 Temporary Dashboard (For This PR)
**Recommendation:** Create

Monitor during rollout (7 days):
- **Files:**
  - `temp/pr-1234-monitoring.yml`
  - `temp/pr-1234-queries.nrql`

**Key Metrics:**
- Endpoint error rate (detect failures immediately)
- Database query latency (catch performance regressions)
- API response time P95 (ensure user experience)

## 📈 Permanent Observability Suggestions

### New Alerts
Add to infrastructure.yml:
```yaml
alerts:
  - name: profile-api-error-rate
    condition: error_rate > 5%
    severity: critical
```

## 🚀 Next Steps
1. Review generated dashboard queries
2. Add temp monitoring files to this PR
3. Monitor during rollout
4. Add permanent config after validation
```

## 🔧 Local Testing

Test the agent locally before pushing:

```bash
# Set environment variables
export CLAUDE_API_KEY="your-key"
export NEWRELIC_API_KEY="your-key"
export GITHUB_TOKEN="your-token"
export GITHUB_REPOSITORY="your-org/your-repo"
export PR_NUMBER="123"

# Run agent
ruby agent.rb
```

## 🎯 Use Cases

### Use Case 1: Temporary Dashboard (PR Monitoring)
**When:** PR adds new features that need rollout monitoring
**Output:** 
- Reference file in infrastructure.yml
- Separate queries file
- Focus on rollout safety metrics

### Use Case 2: Permanent Observability
**When:** New features need long-term monitoring
**Output:**
- Dashboard configurations
- Alert definitions
- SLO monitoring

### Use Case 3: Skip Small PRs
**When:** PR < 50 lines (typos, formatting, etc.)
**Output:** "PR too small - skipping observability"

## 📝 Configuration

### Adjust PR Size Threshold

Edit `agent.rb`:

```ruby
SMALL_PR_THRESHOLD = 50  # Change this value
```

### Customize AI Behavior

Edit `claude.md` to:
- Add your platform's infrastructure.yml format
- Define monitoring patterns
- Set decision rules
- Add example configurations

## 🔒 Security

- Never commit API keys to git
- Use GitHub Secrets for sensitive data
- Agent runs in isolated GitHub Actions container
- No data stored between runs

## 💰 Cost

- **GitHub Actions:** Free (2,000 minutes/month)
- **Claude API:** ~$0.01 per PR analysis
- **NewRelic API:** Free
- **Total:** ~$5 for entire hackathon

## 🐛 Troubleshooting

### "lib directory not found"
Run `./setup.sh` to create lib directory and files

### "Claude API error"
Check `CLAUDE_API_KEY` is set correctly in GitHub Secrets

### "NewRelic query failed"
Verify `NEW_RELIC_API_KEY` has query permissions

### "Agent not running"
Check GitHub Actions logs in your PR's "Checks" tab

## 🚀 Development

### Adding New Tools

Edit `lib/tools.rb`:

```ruby
def definitions
  [
    # Add new tool definition
    {
      name: 'my_new_tool',
      description: 'What it does',
      input_schema: { ... }
    }
  ]
end

def execute(tool_name, input)
  case tool_name
  when 'my_new_tool'
    my_new_tool(input)
  end
end
```

### Improving AI Decisions

Edit `claude.md`:
- Add more examples
- Refine decision rules
- Update output format
- Add platform-specific patterns

## 📚 References

- [Claude API Docs](https://docs.anthropic.com)
- [Octokit Ruby](https://github.com/octokit/octokit.rb)
- [NewRelic NerdGraph](https://docs.newrelic.com/docs/apis/nerdgraph/)
- [GitHub Actions](https://docs.github.com/en/actions)

## 🎉 Demo Tips

For hackathon demo:
1. Show it running on a real PR
2. Highlight autonomous tool usage
3. Emphasize cross-language support
4. Show before/after observability
5. Mention low cost (~$0.01/PR)

## 📄 License

MIT

## 🙋 Support

Open an issue or contact the team for help!
