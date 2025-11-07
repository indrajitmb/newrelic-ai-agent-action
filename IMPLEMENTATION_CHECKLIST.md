# 🚀 Implementation Checklist

## Quick Start - 15 Minute Setup

### Step 1: Update Core Files (5 min)
```bash
# In your newrelic-ai-agent-action directory

# Backup current files
cp lib/tools.rb lib/tools.rb.backup
cp codepulse.rb codepulse.rb.backup
cp context.md context.md.backup

# Replace with updated versions
mv lib/tools_updated.rb lib/tools.rb
mv codepulse_updated.rb codepulse.rb
mv context_updated.md context.md
```

### Step 2: Update Workflow in Target Repo (5 min)
```bash
# In your target repository (e.g., syncsoldier)

# Copy the updated workflow
cp /path/to/newrelic-ai-agent-action/example-workflow-updated.yml \
   .github/workflows/newrelic-ai.yml

# Update the repository reference in the workflow file (line 36)
# Change: repository: your-org/newrelic-ai-agent-action
# To: repository: [your-actual-org]/newrelic-ai-agent-action
```

### Step 3: Test the Setup (5 min)
```bash
# 1. Create a test PR in your target repo
# 2. Comment on the PR: "Constant Vigilance"
# 3. Watch the GitHub Actions tab for the workflow to start
# 4. Should see:
#    - 👀 reaction on your comment
#    - "Starting..." comment from bot
#    - Comprehensive analysis posted after 1-2 minutes
```

---

## What Changed - Summary

### 1. GitHub Action Trigger ✅
**Before:** Triggered on every PR open/update
**After:** Triggered only when you comment "Constant Vigilance"

**Benefits:**
- Saves GitHub Actions minutes
- Run only when needed
- Can re-run analysis after fixing issues
- No unwanted runs on draft PRs

### 2. App Name Detection ✅
**Before:** appName was hardcoded or guessed
**After:** Automatically detects from NewRelic using `get_newrelic_app_name` tool

**Benefits:**
- Correct appName in all NRQL queries
- Handles repos with different app names
- Suggests options if multiple matches
- Clear error if app not found

### 3. Exhaustive Recommendations ✅
**Before:** 1-2 alerts, minimal dashboards
**After:** 4-6+ alerts, 8-15 widget dashboards

**New Coverage:**
- Log statement monitoring (every error/warn log)
- Dependency impact analysis
- Learning from existing dashboards
- Baseline-driven thresholds
- End-to-end transaction tracking

### 4. New Analysis Tools ✅
Added 4 new tools:
1. `get_newrelic_app_name` - Detect correct app name
2. `analyze_log_statements` - Extract error/warn logs
3. `find_dependent_code` - Find code dependencies
4. `learn_from_existing_dashboards` - Match existing patterns

---

## Verification Tests

### Test 1: On-Demand Trigger
```
1. Open any PR in target repo
2. Comment: "Constant Vigilance"
3. Expected: Bot reacts with 👀 and posts "Starting..."
4. Expected: Full analysis posted in 1-2 minutes
```

### Test 2: App Name Detection
```
1. Check the analysis output
2. Look for: "App Name Detected: [name]"
3. Verify all NRQL queries use this app name
4. Expected: No "appName = 'undefined'" or hardcoded names
```

### Test 3: Log Monitoring
```
1. Create PR that adds: logger.error "Payment failed"
2. Trigger analysis
3. Expected: Alert suggested for this specific log message
4. Format: "Error Log: Payment failed" with occurrence threshold
```

### Test 4: Dependency Analysis
```
1. Modify a commonly-used class (e.g., UserService)
2. Trigger analysis
3. Expected: Impact assessment (Low/Medium/High/Critical)
4. Expected: Additional monitoring based on impact level
```

### Test 5: Comprehensive Coverage
```
1. Create PR with:
   - 1 new API endpoint
   - 1 database query
   - 2-3 log statements
2. Trigger analysis
3. Expected minimum output:
   - 1 dashboard with 8+ widgets
   - 4+ alert conditions
   - Log-based alerts
   - Impact analysis
```

---

## Troubleshooting

### Issue: Workflow not triggering
**Check:**
- Workflow file in `.github/workflows/newrelic-ai.yml`
- Comment contains exact phrase "Constant Vigilance"
- PR exists (not an issue)
- Repository has secrets set up

**Fix:**
```yaml
# Verify the condition in workflow:
if: |
  github.event.issue.pull_request &&
  contains(github.event.comment.body, 'Constant Vigilance')
```

### Issue: App name not detected
**Check:**
- NewRelic API key is valid
- App is reporting to NewRelic
- Repository name somewhat matches app name

**Manual override:**
If detection fails, you can hardcode temporarily in prompt:
```ruby
# In codepulse.rb, add to initial prompt:
OVERRIDE: Use appName = 'your-actual-app-name' for all queries
```

### Issue: Not enough recommendations
**Check:**
- Max iterations set to 20 (was 10 before)
- Enhanced prompt is being used (look for "COMPREHENSIVE" in output)
- Tools are returning data (check logs)

**Debug:**
```bash
# Run locally to see tool outputs:
ruby test_local.rb
```

### Issue: Wrong alert thresholds
**Check:**
- Baseline queries are running
- Agent is using baseline data for thresholds

**Expected:**
- Thresholds should be baseline × multiplier
- Not just hardcoded 5% / 10%

---

## Rollback Plan

If something goes wrong:

```bash
# In newrelic-ai-agent-action:
mv lib/tools.rb.backup lib/tools.rb
mv codepulse.rb.backup codepulse.rb
mv context.md.backup context.md

# In target repo:
git checkout HEAD -- .github/workflows/newrelic-ai.yml

# Or use old trigger:
# Change 'issue_comment' back to 'pull_request'
```

---

## Performance Expectations

### Before (Old Version):
- Analysis time: ~30-60 seconds
- Tool calls: ~5-8
- Output: 1-2 alerts, minimal dashboard

### After (Enhanced Version):
- Analysis time: ~1-2 minutes (more thorough)
- Tool calls: ~15-20
- Output: 4-6+ alerts, comprehensive dashboard
- Cost per PR: ~$0.20 (vs $0.10 before)

**Note:** On-demand triggering should keep monthly costs similar or lower despite more thorough analysis.

---

## Next Iteration Ideas

After this works well, consider adding:

1. **Custom Trigger Phrases**
   ```
   "Quick Check" → Fast analysis (fewer tools)
   "Deep Dive" → Maximum analysis (all tools)
   "Compare Staging" → Compare against staging metrics
   ```

2. **Severity Levels**
   ```
   Comment: "Constant Vigilance --severity=high"
   → Only critical monitoring
   ```

3. **Auto-Commit Mode**
   ```
   Comment: "Constant Vigilance --auto-commit"
   → Creates PR with monitoring configs
   ```

4. **Learning Mode**
   ```
   Comment: "Constant Vigilance --learn"
   → Analyzes recent production incidents
   → Suggests monitoring to prevent similar issues
   ```

---

## Support

If you run into issues:

1. Check GitHub Actions logs
2. Look for tool execution errors
3. Verify API keys are set correctly
4. Test tools individually using test_local.rb

Happy monitoring! 🎉
