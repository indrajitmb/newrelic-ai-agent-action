module ContextLoader
  def self.load_context(app_name: nil, github_client: nil)
    # Fetch app name from production.yaml if not provided
    if app_name.nil? && github_client
      app_name = fetch_app_name_from_production_yaml(github_client)
    end
    
    app_name ||= 'YourAppName'
    
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
      return default_context(app_name)
    end
    
    context_content = File.read(context_file)
    
    # Replace placeholder app names with the actual app name from production.yaml
    context_content = context_content.gsub(/appName = ['"]YourAppName['"]/, "appName = '#{app_name}'")
    context_content = context_content.gsub(/appName = ['"]YourApp['"]/, "appName = '#{app_name}'")
    context_content = context_content.gsub(/APP_NAME/, app_name)
    
    <<~CONTEXT
      #{context_content}
      
      You have access to various tools to analyze the pull request and generate observability configurations.
      Always follow the platform configuration format provided in the context above.
      
      Your responses should be clear, actionable, and formatted for GitHub markdown.
      
      IMPORTANT: The application name for this repository is '#{app_name}'. Use this value in all NRQL queries where appName is required.
    CONTEXT
  end
  
  def self.fetch_app_name_from_production_yaml(github_client)
    repo = ENV['GITHUB_REPOSITORY']
    repo_name = repo.split('/').last
    
    # Use specific path pattern: repo_name/environments/production.yaml
    path = "#{repo_name}/environments/production.yaml"
    
    begin
      file = github_client.contents(repo, path: path)
      content = Base64.decode64(file.content)
      
      # Parse YAML and look for NEW_RELIC_APP_NAME
      require 'yaml'
      config = YAML.safe_load(content)
      
      # Look for NEW_RELIC_APP_NAME in env.specific section
      if config && config['env'] && config['env']['specific'] && config['env']['specific']['NEW_RELIC_APP_NAME']
        app_name = config['env']['specific']['NEW_RELIC_APP_NAME']
        puts "✅ Found NEW_RELIC_APP_NAME in #{path}: #{app_name}"
        return app_name
      else
        puts "⚠️  Warning: NEW_RELIC_APP_NAME not found in #{path}"
      end
    rescue Octokit::NotFound
      puts "⚠️  Warning: File not found: #{path}"
    rescue => e
      puts "⚠️  Warning: Error reading #{path}: #{e.message}"
    end
    
    # Fallback: Use repository name
    app_name = repo_name.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
    puts "⚠️  Using repository name as fallback: #{app_name}"
    app_name
  rescue => e
    puts "⚠️  Warning: Failed to fetch app name: #{e.message}, using default"
    'YourAppName'
  end
  
  def self.default_context(app_name = 'YourAppName')
    <<~CONTEXT
      You are a NewRelic observability expert. Analyze code changes and generate appropriate monitoring.
      
      Follow these principles:
      - Temporary dashboards for PR monitoring (rollout phase)
      - Permanent charts and alerts for long-term observability
      - Keep configurations slim and maintainable
      - Focus on actionable metrics
      
      IMPORTANT: The application name for this repository is '#{app_name}'. Use this value in all NRQL queries where appName is required.
    CONTEXT
  end
end
