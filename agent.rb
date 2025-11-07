#!/usr/bin/env ruby

require 'json'
require 'anthropic'
require 'octokit'
require 'faraday'
require_relative 'lib/tools'
require_relative 'lib/context_loader'

class NewRelicAIAgent
  MAX_ITERATIONS = 10
  SMALL_PR_THRESHOLD = 50 # lines changed
  
  def initialize
    @claude = Anthropic::Client.new(api_key: ENV['CLAUDE_API_KEY'])
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
    @conversation << { role: 'user', content: initial_prompt }
    
    iterations = 0
    while iterations < MAX_ITERATIONS
      puts "\n🔄 Iteration #{iterations + 1}/#{MAX_ITERATIONS}"
      response = call_claude
      
      break if response_complete?(response)
      
      if response['stop_reason'] == 'tool_use'
        tool_results = execute_tools(response['content'])
        @conversation << { role: 'user', content: tool_results }
      end
      
      iterations += 1
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
      files: pr.changed_files
    }
  end
  
  def build_initial_prompt(pr_info)
    <<~PROMPT
      You are a NewRelic observability expert analyzing a pull request. Your task is to determine what observability is needed.
      
      ## Application Information:
      - **Application Name**: #{@app_name}
      - **IMPORTANT**: Use "appName = '#{@app_name}'" in all NRQL queries
      
      ## Your Objectives:
      
      1. **Temporary Dashboard** (for monitoring this PR during release):
         - Evaluate if this PR needs temporary monitoring (threshold: >#{SMALL_PR_THRESHOLD} lines changed)
         - If yes, generate NRQL queries for key metrics during rollout
         - Create separate queries file to keep infrastructure.yml slim
      
      2. **Permanent Observability** (long-term charts/alerts):
         - Identify what new permanent charts should be added
         - Determine what alerts should be configured
         - Follow the infrastructure.yml format from context
      
      ## PR Information:
      - **Number**: ##{pr_info[:number]}
      - **Title**: #{pr_info[:title]}
      - **Changes**: #{pr_info[:changes]} lines
      - **Files Changed**: #{pr_info[:files]}
      
      ## Available Tools:
      Use these tools to complete your analysis:
      1. `get_pr_diff` - Fetch the full PR diff
      2. `analyze_file` - Read specific files from the repository
      3. `query_newrelic` - Check existing NewRelic monitoring
      4. `check_existing_infrastructure` - Read current infrastructure.yml
      5. `create_temp_dashboard_files` - Generate temporary dashboard config
      6. `suggest_permanent_config` - Generate permanent observability config
      
      ## Decision Rules:
      - Small changes (<#{SMALL_PR_THRESHOLD} lines): No temporary dashboard needed
      - New endpoints/APIs: Need both temporary and permanent monitoring
      - Database changes: Monitor query performance
      - Background jobs: Monitor success rates and timing
      - Critical paths: Set up SLO alerts
      
      Start by fetching the PR diff and analyzing the changes.
    PROMPT
  end
  
  def call_claude
    response = @claude.messages(
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 4096,
      system: @context,
      messages: @conversation,
      tools: @tools.definitions
    )
    
    @conversation << { role: 'assistant', content: response['content'] }
    response
  end
  
  def execute_tools(content)
    results = []
    
    content.each do |block|
      next unless block['type'] == 'tool_use'
      
      tool_name = block['name']
      tool_input = block['input']
      
      puts "  🔧 Executing: #{tool_name}"
      result = @tools.execute(tool_name, tool_input)
      
      results << {
        type: 'tool_result',
        tool_use_id: block['id'],
        content: result.to_json
      }
    end
    
    results
  end
  
  def response_complete?(response)
    response['stop_reason'] == 'end_turn'
  end
  
  def post_final_results
    # Extract final message from conversation
    final_message = @conversation.last[:content]
      .select { |block| block['type'] == 'text' }
      .map { |block| block['text'] }
      .join("\n")
    
    # Add header
    formatted_message = "🤖 **NewRelic AI Agent - Observability Analysis**\n\n#{final_message}"
    
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
