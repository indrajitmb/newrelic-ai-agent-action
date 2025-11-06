#!/usr/bin/env ruby

require 'json'
require 'openai'
require 'octokit'
require 'faraday'
require_relative 'lib/tools'
require_relative 'lib/context_loader'

class NewRelicAIAgent
  MAX_ITERATIONS = 10
  SMALL_PR_THRESHOLD = 50 # lines changed
  
  def initialize
    @openai = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    @github = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    @context = ContextLoader.load_context
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
        tool_results = execute_tools(response.dig('choices', 0, 'message', 'tool_calls'))
        @conversation << { role: 'tool', content: tool_results }
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
    
    final_message = assistant_messages.last || "Analysis complete."
    
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

