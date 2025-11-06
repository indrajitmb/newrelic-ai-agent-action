module ContextLoader
  def self.load_context
    # Check for generic context.md first, then fallback to claude.md for backward compatibility
    context_md_path = File.join(__dir__, '../context.md')
    claude_md_path = File.join(__dir__, '../claude.md')
    
    context_file = if File.exist?(context_md_path)
      context_md_path
    elsif File.exist?(claude_md_path)
      claude_md_path
    else
      nil
    end
    
    unless context_file
      puts "⚠️  Warning: context.md or claude.md not found, using minimal context"
      return default_context
    end
    
    context_content = File.read(context_file)
    
    <<~CONTEXT
      #{context_content}
      
      You have access to various tools to analyze the pull request and generate observability configurations.
      Always follow the platform configuration format provided in the context above.
      
      Your responses should be clear, actionable, and formatted for GitHub markdown.
    CONTEXT
  end
  
  def self.default_context
    <<~CONTEXT
      You are a NewRelic observability expert. Analyze code changes and generate appropriate monitoring.
      
      Follow these principles:
      - Temporary dashboards for PR monitoring (rollout phase)
      - Permanent charts and alerts for long-term observability
      - Keep configurations slim and maintainable
      - Focus on actionable metrics
    CONTEXT
  end
end

