#!/usr/bin/env ruby

# Local testing script for NewRelic AI Agent
# Usage: ruby test_local.rb

require_relative 'agent'

puts "🧪 NewRelic AI Agent - Local Test Mode"
puts "=" * 50

# Check environment variables
required_vars = ['CLAUDE_API_KEY', 'NEWRELIC_API_KEY', 'GITHUB_TOKEN', 'GITHUB_REPOSITORY', 'PR_NUMBER']
missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

if missing_vars.any?
  puts "❌ Missing required environment variables:"
  missing_vars.each { |var| puts "   - #{var}" }
  puts "\n📝 Set them like this:"
  puts "export CLAUDE_API_KEY='your-key'"
  puts "export NEWRELIC_API_KEY='your-key'"
  puts "export GITHUB_TOKEN='your-token'"
  puts "export GITHUB_REPOSITORY='your-org/your-repo'"
  puts "export PR_NUMBER='123'"
  exit 1
end

puts "✅ All environment variables set"
puts "📦 Repository: #{ENV['GITHUB_REPOSITORY']}"
puts "🔢 PR Number: #{ENV['PR_NUMBER']}"
puts ""

begin
  # Run the agent
  agent = NewRelicAIAgent.new
  agent.run
  
  puts "\n✅ Test completed successfully!"
rescue => e
  puts "\n❌ Test failed:"
  puts "   Error: #{e.message}"
  puts "\n📚 Stack trace:"
  puts e.backtrace.join("\n")
  exit 1
end
