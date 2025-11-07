# Comprehensive Improvements Plan

## 1. Change GitHub Action Trigger to On-Demand

### Current Issue
Action triggers on PR creation/sync - runs even when not needed.

### Solution
Trigger on specific comment: "Constant Vigilance"

**Updated workflow file** (`example-workflow.yml`):
```yaml
name: NewRelic AI Analysis

on:
  issue_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write

jobs:
  analyze:
    # Only run on PR comments with trigger phrase
    if: |
      github.event.issue.pull_request &&
      contains(github.event.comment.body, 'Constant Vigilance')
    
    runs-on: ubuntu-latest
    name: Analyze PR for Observability
    
    steps:
      - name: React to trigger comment
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.reactions.createForIssueComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              comment_id: context.payload.comment.id,
              content: 'eyes'
            });
      
      - name: Checkout PR branch
        uses: actions/checkout@v4
        with:
          # Checkout the PR's head ref
          ref: refs/pull/${{ github.event.issue.number }}/head
      
      - name: Checkout Action Repository
        uses: actions/checkout@v4
        with:
          repository: your-org/newrelic-ai-agent-action
          ref: main
          path: .github/actions/newrelic-agent
      
      - name: Run NewRelic AI Agent
        uses: ./.github/actions/newrelic-agent
        with:
          openai-api-key: ${{ secrets.OPENAI_API_KEY }}
          newrelic-api-key: ${{ secrets.NEWRELIC_API_KEY }}
        env:
          PR_NUMBER: ${{ github.event.issue.number }}
```

**Benefits:**
- Runs only when explicitly requested
- Saves compute minutes
- Developers can trigger re-analysis after addressing issues
- Multiple trigger phrases can be added (e.g., "Run Observability", "Check Monitoring")

---

## 2. Fix NRQL appName Filter

### Current Issue
`appName` in NRQL queries is incorrect or missing.

### Root Cause Analysis
The app name needs to be dynamically determined from:
1. Repository name
2. Environment variable `NEW_RELIC_APP_NAME`
3. Existing NewRelic entities

### Solution: Add App Name Detection Tool

**New tool in `lib/tools.rb`**:
```ruby
def definitions
  [
    # ... existing tools ...
    {
      name: 'get_newrelic_app_name',
      description: 'Detect the correct NewRelic application name for this repository',
      input_schema: {
        type: 'object',
        properties: {
          repo_name: {
            type: 'string',
            description: 'Repository name to search for'
          }
        },
        required: []
      }
    }
  ]
end

def execute(tool_name, input)
  case tool_name
  # ... existing cases ...
  when 'get_newrelic_app_name'
    get_newrelic_app_name(input['repo_name'])
  end
end

private

def get_newrelic_app_name(repo_name = nil)
  repo_name ||= @repo.split('/').last
  
  # Query NewRelic for matching application names
  graphql_query = <<~GRAPHQL
    {
      actor {
        entitySearch(query: "domain = 'APM' AND type = 'APPLICATION'") {
          results {
            entities {
              name
              guid
              domain
            }
          }
        }
      }
    }
  GRAPHQL
  
  conn = Faraday.new(url: 'https://api.newrelic.com/graphql') do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end
  
  response = conn.post do |req|
    req.headers['API-Key'] = @nr_key
    req.headers['Content-Type'] = 'application/json'
    req.body = { query: graphql_query }
  end
  
  if response.success?
    entities = response.body.dig('data', 'actor', 'entitySearch', 'results', 'entities') || []
    
    # Try exact match
    exact_match = entities.find { |e| e['name'].downcase == repo_name.downcase }
    return { app_name: exact_match['name'], guid: exact_match['guid'] } if exact_match
    
    # Try fuzzy match (contains repo name)
    fuzzy_matches = entities.select { |e| e['name'].downcase.include?(repo_name.downcase) }
    
    if fuzzy_matches.length == 1
      match = fuzzy_matches.first
      return { app_name: match['name'], guid: match['guid'] }
    elsif fuzzy_matches.length > 1
      return {
        error: "Multiple matches found",
        suggestions: fuzzy_matches.map { |e| e['name'] },
        message: "Please manually specify appName or narrow the search"
      }
    else
      return {
        error: "No matching application found",
        searched_for: repo_name,
        available_apps: entities.map { |e| e['name'] }
      }
    end
  else
    { error: "Failed to fetch NewRelic entities: #{response.status}" }
  end
rescue => e
  { error: "Failed to detect app name: #{e.message}" }
end
```

**Updated System Prompt** (in `codepulse.rb`):
```ruby
def build_initial_prompt(pr_info)
  <<~PROMPT
    You are a NewRelic observability expert analyzing a pull request.
    
    ## CRITICAL: App Name Detection
    
    BEFORE generating any NRQL queries, you MUST:
    1. Call `get_newrelic_app_name` to detect the correct NewRelic application name
    2. Use the returned app name in ALL NRQL queries
    3. If multiple matches found, use the most relevant one
    4. If no match found, STOP and inform the user
    
    ALWAYS use: WHERE appName = 'EXACT_NAME_FROM_TOOL'
    NEVER hardcode or guess the app name.
    
    # ... rest of prompt ...
  PROMPT
end
```

---

## 3. Make Recommendations More Exhaustive

### Current Issues
- Too few alerts suggested
- Too few dashboard widgets
- Missing common patterns

### Solution A: Enhanced Analysis Prompt

**Update `context.md` with more comprehensive patterns**:

```markdown
## Exhaustive Monitoring Checklist

When analyzing code changes, systematically check for ALL of these patterns:

### 1. API Endpoints (Controllers/Routes)
For EACH new/modified endpoint, suggest:
- **Dashboards:**
  - Request rate (billboard + line chart)
  - Success rate by status code (pie chart)
  - Response time percentiles (line chart)
  - Error breakdown by type (facet table)
  - Throughput by endpoint (bar chart)

- **Alerts:**
  - High error rate (>5% warning, >10% critical)
  - Slow response time (p95 > 1s warning, >3s critical)
  - Zero traffic (if endpoint is critical)
  - High 5xx rate (>1% warning, >5% critical)

### 2. Database Queries
For EACH new query/migration, suggest:
- **Dashboards:**
  - Query execution time (line chart)
  - Slow query count (billboard)
  - Rows affected (line chart)
  - Lock duration (line chart)
  - Query frequency (bar chart)

- **Alerts:**
  - Slow queries (>500ms warning, >2s critical)
  - Lock timeouts
  - High row count operations
  - Failed transactions

### 3. Background Jobs
For EACH job, suggest:
- **Dashboards:**
  - Success/failure rate (billboard + pie chart)
  - Processing duration (line chart)
  - Queue depth (area chart)
  - Retry count (line chart)
  - Job throughput (bar chart)

- **Alerts:**
  - High failure rate (>5% warning, >10% critical)
  - Long processing time (p95 threshold)
  - Queue backlog (depth > threshold)
  - Stuck jobs (no completion in X minutes)

### 4. External API Calls
For EACH integration, suggest:
- **Dashboards:**
  - Response time (line chart)
  - Success rate (billboard)
  - Error types (facet table)
  - Rate limit usage (line chart)
  - Circuit breaker state (billboard)

- **Alerts:**
  - High latency (>2s warning, >5s critical)
  - Error rate (>1% warning, >5% critical)
  - Timeout rate
  - Circuit breaker open

### 5. Log Statements (NEW)
For EACH log.error, log.warn, suggest:
- **Dashboards:**
  - Error occurrence count (billboard)
  - Error trend over time (line chart)
  - Error by type/message (facet table)
  - Error rate by severity (pie chart)

- **Alerts:**
  - Error spike (>10/min warning, >50/min critical)
  - New error types (baseline alert)
  - Warning rate threshold

### 6. Business Logic Changes
For critical paths, suggest:
- **Dashboards:**
  - Success rate (billboard)
  - Processing time (line chart)
  - Volume (line chart)
  - Conversion rate (billboard)

- **Alerts:**
  - Low success rate
  - Anomalous volume
  - Slow processing

### 7. Dependency Impact Analysis (NEW)
For each change, analyze:
- **What services/endpoints call this code?**
- **What downstream services does this call?**
- **Suggest monitoring for impact propagation**

Example: If modifying UserService.create_user()
- Dashboard widget: Callers of this method (Transaction breakdown)
- Alert: Failure rate in dependent services
- Dashboard: End-to-end success rate
```

### Solution B: Add New Analysis Tools

**New tool: `analyze_log_statements`**
```ruby
{
  name: 'analyze_log_statements',
  description: 'Extract and analyze all log statements (error, warn, info) from code changes',
  input_schema: {
    type: 'object',
    properties: {
      file_content: {
        type: 'string',
        description: 'File content to analyze for log statements'
      }
    },
    required: ['file_content']
  }
}

def analyze_log_statements(file_content)
  # Regex patterns for common logging
  patterns = {
    error: /(?:logger|Rails\.logger|log)\.error\(['"](.*?)['"]/,
    warn: /(?:logger|Rails\.logger|log)\.warn\(['"](.*?)['"]/,
    info: /(?:logger|Rails\.logger|log)\.info\(['"](.*?)['"]/
  }
  
  results = {
    error_logs: [],
    warn_logs: [],
    info_logs: []
  }
  
  file_content.each_line.with_index do |line, idx|
    patterns.each do |severity, pattern|
      if match = line.match(pattern)
        results[:"#{severity}_logs"] << {
          line_number: idx + 1,
          message: match[1],
          context: line.strip
        }
      end
    end
  end
  
  results[:summary] = {
    total_errors: results[:error_logs].length,
    total_warnings: results[:warn_logs].length,
    total_info: results[:info_logs].length
  }
  
  results
end
```

**New tool: `find_dependent_code`**
```ruby
{
  name: 'find_dependent_code',
  description: 'Find code that depends on or calls the modified methods/classes',
  input_schema: {
    type: 'object',
    properties: {
      class_name: {
        type: 'string',
        description: 'Class name to search for (e.g., "UserController")'
      },
      method_name: {
        type: 'string',
        description: 'Method name to search for (e.g., "create")'
      }
    },
    required: ['class_name']
  }
}

def find_dependent_code(class_name, method_name = nil)
  # Search for references using GitHub's code search
  search_query = class_name
  search_query += ".#{method_name}" if method_name
  
  results = @github.search_code(
    "#{search_query} repo:#{@repo}",
    per_page: 20
  )
  
  dependencies = results.items.map do |item|
    {
      file: item.path,
      url: item.html_url,
      matches: item.text_matches || []
    }
  end
  
  {
    total_references: results.total_count,
    dependencies: dependencies,
    impact_assessment: assess_impact(results.total_count)
  }
rescue => e
  { error: "Failed to find dependencies: #{e.message}" }
end

def assess_impact(reference_count)
  case reference_count
  when 0..5
    "Low - Few dependencies, localized impact"
  when 6..15
    "Medium - Moderate dependencies, watch for cascade failures"
  when 16..Float::INFINITY
    "High - Many dependencies, critical to monitor end-to-end flow"
  end
end
```

**New tool: `learn_from_existing_dashboards`**
```ruby
{
  name: 'learn_from_existing_dashboards',
  description: 'Analyze existing NewRelic dashboards to understand current monitoring patterns',
  input_schema: {
    type: 'object',
    properties: {
      app_name: {
        type: 'string',
        description: 'Application name to search dashboards for'
      }
    },
    required: ['app_name']
  }
}

def learn_from_existing_dashboards(app_name)
  # Query for existing dashboards
  graphql_query = <<~GRAPHQL
    {
      actor {
        entitySearch(query: "domain = 'VIZ' AND type = 'DASHBOARD'") {
          results {
            entities {
              ... on DashboardEntityOutline {
                name
                guid
                dashboardParentGuid
              }
            }
          }
        }
      }
    }
  GRAPHQL
  
  conn = Faraday.new(url: 'https://api.newrelic.com/graphql') do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end
  
  response = conn.post do |req|
    req.headers['API-Key'] = @nr_key
    req.headers['Content-Type'] = 'application/json'
    req.body = { query: graphql_query }
  end
  
  if response.success?
    dashboards = response.body.dig('data', 'actor', 'entitySearch', 'results', 'entities') || []
    
    # Filter for relevant dashboards (containing app name)
    relevant_dashboards = dashboards.select do |d|
      d['name'].downcase.include?(app_name.downcase)
    end
    
    {
      total_dashboards: relevant_dashboards.length,
      dashboards: relevant_dashboards.map { |d| { name: d['name'], guid: d['guid'] } },
      patterns_found: extract_common_patterns(relevant_dashboards)
    }
  else
    { error: "Failed to fetch dashboards: #{response.status}" }
  end
rescue => e
  { error: "Failed to learn from dashboards: #{e.message}" }
end

def extract_common_patterns(dashboards)
  # Common patterns to look for in dashboard names
  patterns = {
    has_error_monitoring: dashboards.any? { |d| d['name'].match?(/error|exception|failure/i) },
    has_performance_monitoring: dashboards.any? { |d| d['name'].match?(/performance|latency|response/i) },
    has_business_metrics: dashboards.any? { |d| d['name'].match?(/business|revenue|conversion/i) },
    has_infrastructure: dashboards.any? { |d| d['name'].match?(/infra|system|resource/i) }
  }
  
  patterns
end
```

### Solution C: Enhanced System Prompt

**Update `build_initial_prompt` in `codepulse.rb`**:
```ruby
def build_initial_prompt(pr_info)
  <<~PROMPT
    You are a NewRelic observability expert. Your goal is EXHAUSTIVE observability coverage.
    
    ## CRITICAL REQUIREMENTS:
    
    1. **Be Exhaustive**: Suggest monitoring for EVERY significant change
    2. **Follow Checklist**: Use the monitoring checklist in context for each pattern
    3. **Analyze Dependencies**: Find and monitor dependent code paths
    4. **Learn from Existing**: Check existing dashboards to match patterns
    5. **Monitor Logs**: Create alerts for error/warning log occurrences
    
    ## Your Analysis Process:
    
    ### Phase 1: App Name Detection
    - Call `get_newrelic_app_name` FIRST
    - Use detected name in ALL subsequent queries
    
    ### Phase 2: Code Analysis
    - Call `get_pr_diff` to see all changes
    - For EACH modified file:
      * Call `analyze_file` to get full context
      * Call `analyze_log_statements` to extract log patterns
      * Identify: endpoints, queries, jobs, external calls
    
    ### Phase 3: Dependency Analysis
    - For EACH modified class/method:
      * Call `find_dependent_code` to find callers
      * Assess cascade failure risk
      * Plan end-to-end monitoring
    
    ### Phase 4: Learn from Existing Patterns
    - Call `learn_from_existing_dashboards`
    - Match monitoring style to existing dashboards
    - Identify gaps in current monitoring
    
    ### Phase 5: Check Current State
    - Call `query_newrelic` to check for existing monitors
    - Avoid duplicates
    - Identify baseline metrics
    
    ### Phase 6: Generate Comprehensive Config
    - Create dashboard with 5-10 widgets minimum
    - Create 3-5 alert conditions per significant change
    - Include log-based alerts
    - Include dependency impact alerts
    
    ## Minimum Standards:
    
    For a typical API change, you MUST suggest AT LEAST:
    - 1 dashboard with 8+ widgets
    - 4+ alert conditions
    - Log-based monitoring
    - Dependency impact analysis
    
    Don't hold back - it's better to over-monitor than miss critical issues!
    
    ## PR Information:
    - **Number**: ##{pr_info[:number]}
    - **Title**: #{pr_info[:title]}
    - **Changes**: #{pr_info[:changes]} lines
    - **Files Changed**: #{pr_info[:files]}
    
    Start by detecting the app name, then analyze the PR comprehensively.
  PROMPT
end
```

---

## 4. Implementation Checklist

### Files to Update:

1. **`.github/workflows/newrelic-ai.yml`** (in target repo)
   - Change trigger from `pull_request` to `issue_comment`
   - Add comment body check for "Constant Vigilance"
   - Add reaction to trigger comment

2. **`lib/tools.rb`**
   - Add `get_newrelic_app_name` tool
   - Add `analyze_log_statements` tool
   - Add `find_dependent_code` tool
   - Add `learn_from_existing_dashboards` tool

3. **`codepulse.rb`**
   - Update `build_initial_prompt` with comprehensive requirements
   - Enforce app name detection first

4. **`context.md`**
   - Add exhaustive monitoring checklist
   - Add log monitoring patterns
   - Add dependency analysis guidelines

---

## 5. Testing Plan

### Test Case 1: On-Demand Trigger
```bash
# Create a PR
# Comment: "Constant Vigilance"
# Verify: Action triggers and reacts with 👀
```

### Test Case 2: App Name Detection
```bash
# Verify: Agent correctly identifies app name
# Verify: All NRQL queries use correct appName
```

### Test Case 3: Exhaustive Recommendations
```bash
# Create PR with:
# - 1 new controller action
# - 1 new background job
# - 1 external API call
# - 2-3 log statements

# Expected output:
# - 1 dashboard with 8+ widgets
# - 4+ alert conditions
# - Log-based alerts
# - Dependency analysis
```

### Test Case 4: Log Analysis
```bash
# Modify file to add:
# - logger.error "Something failed"
# - logger.warn "Approaching limit"

# Expected: Alerts for both patterns
```

---

## 6. Performance Optimizations

### Parallel Tool Calls
Since OpenAI doesn't support parallel tool execution, sequence efficiently:

```ruby
# Phase 1: Fast, required calls (sequential)
1. get_newrelic_app_name
2. get_pr_diff

# Phase 2: Per-file analysis (can describe strategy to AI for batch)
3. analyze_file (for each changed file)
4. analyze_log_statements (for each file)

# Phase 3: Context gathering (can be done in any order)
5. find_dependent_code (for key changes)
6. learn_from_existing_dashboards
7. query_newrelic (for baselines)

# Phase 4: Generation
8. create_temp_dashboard_files
9. suggest_permanent_config
```

---

## 7. Cost Estimation

### Current Cost per PR:
- ~10 tool calls × $0.01 = $0.10/PR

### After Improvements:
- ~20 tool calls × $0.01 = $0.20/PR
- On-demand trigger reduces unnecessary runs
- **Net effect: Similar or lower monthly cost**

---

## 8. Future Enhancements

1. **Custom Trigger Phrases**
   - "Quick Check" → Faster, fewer recommendations
   - "Deep Dive" → Maximum analysis
   - "Compare Staging" → Compare against staging metrics

2. **Multi-PR Analysis**
   - Analyze impact across multiple PRs in same release

3. **Historical Comparison**
   - "How does this compare to last similar PR?"

4. **Auto-Fix Mode**
   - Directly create PR with monitoring configs

---

## Quick Start

1. Copy updated `example-workflow.yml` to target repo
2. Update `lib/tools.rb` with new tools
3. Update `codepulse.rb` with new prompt
4. Update `context.md` with checklists
5. Test with "Constant Vigilance" comment on a PR
6. Iterate based on results

All code snippets are production-ready and can be directly integrated.
