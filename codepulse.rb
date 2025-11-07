#!/usr/bin/env ruby

require 'json'
require 'openai'
require 'octokit'
require 'faraday'
require_relative 'lib/tools'
require_relative 'lib/context_loader'

class NewRelicAIAgent
  MAX_ITERATIONS = 15
  SMALL_PR_THRESHOLD = 50 # lines changed
  
  def initialize
    @openai = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    @github = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    @app_name = ContextLoader.fetch_app_name_from_production_yaml(@github)
    @context = ContextLoader.load_context(app_name: @app_name, github_client: @github)
    @conversation = []
    @tools = Tools.new(
      github: @github,
      newrelic_key: ENV['NEWRELIC_API_KEY']
    )
  end
  
  def run
    puts "🤖 Starting NewRelic AI Agent..."
    pr_info = get_pr_info
    puts "📊 Analyzing PR ##{pr_info[:number]}: #{pr_info[:title]}"
    puts "📝 Changes: #{pr_info[:changes]} lines across #{pr_info[:files]} files"
    
    # Skip small PRs
    if pr_info[:changes] < SMALL_PR_THRESHOLD
      puts "⏭️  PR too small - skipping"
      post_comment("🤖 **NewRelic AI Agent**\n\nPR is too small (#{pr_info[:changes]} lines changed) to warrant observability suggestions. No action needed.")
      return
    end
    
    initial_prompt = build_initial_prompt(pr_info)
    
    # Initialize conversation with system message and user message
    @conversation << { role: 'system', content: @context }
    @conversation << { role: 'user', content: initial_prompt }
    
    iterations = 0
    while iterations < MAX_ITERATIONS
      puts "\n🔄 Iteration #{iterations + 1}/#{MAX_ITERATIONS}"
      response = call_openai
      
      break if response_complete?(response)
      
      if response.dig('choices', 0, 'finish_reason') == 'tool_calls'
        execute_tools(response.dig('choices', 0, 'message', 'tool_calls'))
      end
      
      iterations += 1
    end
    
    if iterations >= MAX_ITERATIONS
      puts "\n⚠️  Reached maximum iterations - completing analysis with current results"
    end

    puts "\n✅ Analysis complete!"
    post_final_results
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.join("\n")
    post_comment("🤖 **NewRelic AI Agent**\n\n❌ Error occurred during analysis: #{e.message}")
  end
  
  private
  
  def get_pr_info
    repo = ENV['GITHUB_REPOSITORY']
    pr_number = ENV['PR_NUMBER'].to_i
    pr = @github.pull_request(repo, pr_number)
    
    {
      number: pr_number,
      title: pr.title,
      changes: pr.additions + pr.deletions,
      files: pr.changed_files,
      description: pr.body || "No description provided"
    }
  end
  
  def build_initial_prompt(pr_info)
    <<~PROMPT
      You are a NewRelic observability expert. Your goal is COMPREHENSIVE observability coverage.

      ## Application Information:
      - **Application Name**: #{@app_name}
      - **IMPORTANT**: Use "appName = '#{@app_name}'" in all NRQL queries
      
      ## Your Objectives:

      This is NOT about minimal monitoring - it's about comprehensive coverage that prevents production incidents.

      ### Mission Statement:
      "Generate monitoring that would make a production engineer confident to deploy this change at 2 AM on Friday before a holiday weekend."

      ## 📋 MANDATORY ANALYSIS WORKFLOW:

      ### Phase 1: App Name Detection (CRITICAL - DO THIS FIRST)
      1. Call `get_newrelic_app_name` immediately
      2. If it fails or returns multiple matches:
         - Note the issue clearly
         - Pick the most relevant match if suggestions exist
         - Proceed with that name (we can refine later)
      3. Store the app name and use it in EVERY subsequent NRQL query

      ### Phase 2: Deep Code Analysis (Be Thorough)
      1. Call `get_pr_diff` to understand all changes
      2. For EACH modified file (yes, every single one):
         a. Call `analyze_file` to get full context
         b. Call `analyze_log_statements` to find all logging
         c. Identify these patterns:
            - New/modified API endpoints
            - Database queries (ActiveRecord, raw SQL)
            - Background jobs (Sidekiq, delayed_job)
            - External API calls (HTTP, GraphQL)
            - Business logic changes
            - Error handling patterns

      ### Phase 3: Dependency Impact Analysis (New Requirement)
      For EACH significant class/method change:
      1. Call `find_dependent_code` with class name
      2. Note the impact level (Low/Medium/High/Critical)
      3. If impact is Medium or higher:
         - Plan end-to-end monitoring
         - Consider cascade failure scenarios
         - Add dependent service monitoring

      ### Phase 4: Learn from Existing Patterns
      1. Call `learn_from_existing_dashboards` with the detected app name
      2. Note the common patterns in existing dashboards
      3. Match your recommendations to existing style
      4. Identify and fill any gaps

      ### Phase 5: Baseline Metrics (Important Context)
      1. Call `query_newrelic` to get baseline metrics:
         - Current error rate: SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'APP_NAME' SINCE 7 days ago
         - Current throughput: SELECT count(*) FROM Transaction WHERE appName = 'APP_NAME' SINCE 7 days ago
         - Average response time: SELECT average(duration) FROM Transaction WHERE appName = 'APP_NAME' SINCE 7 days ago
      2. Use these baselines to set realistic alert thresholds

      ### Phase 6: Comprehensive Config Generation
      Now generate monitoring that covers:

      #### A. Dashboards (Aim for 8-15 widgets per dashboard)
      For EACH significant change, create dashboard sections with:
      - **Golden Signals** (3-4 widgets):
        * Request rate (billboard + line chart)
        * Error rate (billboard + line chart)
        * Latency (p50, p95, p99 - line chart)
        * Saturation/throughput (line chart)

      - **Detailed Breakdowns** (3-5 widgets):
        * Errors by type (facet_table)
        * Performance by endpoint (bar_chart)
        * Status code distribution (pie_chart)
        * Request volume by time (area_chart)

      - **Dependency Tracking** (2-3 widgets):
        * External call success rates (billboard)
        * Database query performance (line_chart)
        * Queue depths (line_chart if applicable)

      - **Log-Based Monitoring** (2-3 widgets):
        * Error log occurrences (billboard + line_chart)
        * Warning log patterns (facet_table)
        * Critical error types (pie_chart)

      #### B. Alerts (Minimum 4-6 per significant change)
      For EACH endpoint/job/integration, create:
      1. **Error Rate Alert** (REQUIRED)
         - Warning: >5% errors
         - Critical: >10% errors
         - Based on actual baseline + margin

      2. **Performance Alert** (REQUIRED)
         - Warning: p95 > baseline × 2
         - Critical: p95 > baseline × 3

      3. **Log-Based Alerts** (for each error/warn log)
         - Error logs: >5/min warning, >20/min critical
         - Warning logs: >20/min warning, >100/min critical
      
      4. **Dependency Alerts** (if applicable)
         - External API failures: >1% warning, >5% critical
         - Database slow queries: >500ms warning, >2s critical
         - Queue backlog: threshold based on normal load
      
      5. **Business Impact Alerts** (for user-facing changes)
         - Zero traffic (if critical endpoint)
         - Conversion rate drops
         - Success rate below SLO
      
      6. **Cascade Failure Alerts** (for high-impact changes)
         - Downstream service error spikes
         - Circuit breaker opens
         - Timeout rate increases

      ## 📊 OUTPUT REQUIREMENTS:

      Your final response MUST include:
      1. **Impact Assessment**: From dependency analysis
      2. **Baseline Metrics**: Current performance to compare against
      3. **Dashboard Configuration**: Complete YAML with 8-15 widgets
      4. **Alert Configuration**: 4-6 alerts minimum (more for complex changes)
      5. **Log Monitoring**: All error/warn logs with occurrence alerts
      6. **Next Steps**: Clear action items

      ## ⚠️ QUALITY STANDARDS:

      A "good" analysis includes:
      - ✅ At least 1 comprehensive dashboard with 8+ widgets
      - ✅ At least 4 alert conditions (more is better)
      - ✅ Log-based monitoring for every error/warn log
      - ✅ Dependency impact analysis
      - ✅ All NRQL queries use correct appName
      - ✅ Alert thresholds based on actual baselines
      - ✅ Clear visualization type choices (billboard, line_chart, facet_table, etc.)

      An "excellent" analysis includes:
      - ✨ Multiple dashboard pages for different audiences
      - ✨ 6+ alerts covering all failure modes
      - ✨ Proactive monitoring (predict issues before they happen)
      - ✨ End-to-end transaction tracking
      - ✨ Business impact correlation

      ## 🚫 COMMON MISTAKES TO AVOID:

      - ❌ Suggesting only 1-2 alerts (too minimal)
      - ❌ Generic thresholds without baseline data
      - ❌ Forgetting to monitor logs
      - ❌ Ignoring dependency impact
      - ❌ Missing appName in NRQL queries
      - ❌ Wrong visualization types (bar_chart with TIMESERIES, etc.)
      - ❌ Saying "monitoring looks good" when you haven't checked thoroughly

      ## 📝 PR INFORMATION:
      - **Number**: ##{pr_info[:number]}
      - **Title**: #{pr_info[:title]}
      - **Description**: #{pr_info[:description]}
      - **Changes**: #{pr_info[:changes]} lines across #{pr_info[:files]} files

      ## 🚀 START YOUR ANALYSIS:

      Begin by calling `get_newrelic_app_name` right now. Then work through each phase systematically.

      Remember: Better to over-monitor and dial back than to miss a critical production issue.
      Your recommendations could prevent a 2 AM outage!
    PROMPT
  end
  
  def call_openai
    # Convert tools to OpenAI function calling format
    functions = @tools.definitions.map do |tool|
      {
        type: 'function',
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:input_schema]
        }
      }
    end
    
    response = @openai.chat(
      parameters: {
        model: 'gpt-4-turbo-preview',
        messages: @conversation,
        tools: functions,
        tool_choice: 'auto',
        max_tokens: 4096
      }
    )
    
    # Add assistant's response to conversation
    assistant_message = response.dig('choices', 0, 'message')
    @conversation << {
      role: 'assistant',
      content: assistant_message['content'],
      tool_calls: assistant_message['tool_calls']
    }.compact
    
    response
  end
  
  def execute_tools(tool_calls)
    return [] unless tool_calls
    
    results = []
    
    tool_calls.each do |tool_call|
      tool_name = tool_call.dig('function', 'name')
      tool_input = JSON.parse(tool_call.dig('function', 'arguments'))
      tool_id = tool_call['id']
      
      puts "  🔧 Executing: #{tool_name}"
      result = @tools.execute(tool_name, tool_input)
      
      # OpenAI expects tool results in a specific format
      @conversation << {
        role: 'tool',
        tool_call_id: tool_id,
        content: result.to_json
      }
    end
    
    results
  end
  
  def response_complete?(response)
    finish_reason = response.dig('choices', 0, 'finish_reason')
    finish_reason == 'stop' || finish_reason == 'end_turn'
  end
  
  def post_final_results
    # Extract final message from conversation
    assistant_messages = @conversation
      .select { |msg| msg[:role] == 'assistant' && msg[:content] }
      .map { |msg| msg[:content] }
    
    final_message = assistant_messages.last || "Analysis complete - see detailed recommendations above."
    
    # Add header with metadata
    formatted_message = <<~COMMENT
      🤖 **NewRelic AI Agent - Comprehensive Observability Analysis**

      *Enhanced with: Log monitoring, Dependency analysis, Existing pattern learning*

      ---

      #{final_message}

      ---

      💡 **Pro Tips:**
      - Alert thresholds are based on baseline metrics - adjust based on your SLOs
      - Dashboard widgets use recommended visualization types for each metric
      - Log-based alerts help catch issues before they escalate
      - Dependency monitoring helps identify cascade failures early

      🔄 **To Re-Run Analysis:** Comment "Constant Vigilance" on this PR
    COMMENT
    
    puts "\n📤 Posting results to PR..."
    post_comment(formatted_message)
  end
  
  def post_comment(body)
    repo = ENV['GITHUB_REPOSITORY']
    pr_number = ENV['PR_NUMBER'].to_i
    @github.add_comment(repo, pr_number, body)
    puts "✅ Comment posted!"
  end
end

# Run the agent
if __FILE__ == $0
  NewRelicAIAgent.new.run
end
