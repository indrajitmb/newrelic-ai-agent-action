class Tools
  def initialize(github:, newrelic_key:)
    @github = github
    @nr_key = newrelic_key
    @repo = ENV['GITHUB_REPOSITORY']
    @pr_number = ENV['PR_NUMBER'].to_i
  end
  
  def definitions
    [
      {
        name: 'get_newrelic_app_name',
        description: 'Detect the correct NewRelic application name for this repository. MUST be called FIRST before any NRQL queries.',
        input_schema: {
          type: 'object',
          properties: {
            repo_name: {
              type: 'string',
              description: 'Repository name to search for (optional, uses current repo if not provided)'
            }
          },
          required: []
        }
      },
      {
        name: 'get_pr_diff',
        description: 'Get the full diff of PR changes to understand what code was added, modified, or removed',
        input_schema: {
          type: 'object',
          properties: {},
          required: []
        }
      },
      {
        name: 'analyze_file',
        description: 'Read and analyze a specific file from the repository to understand its current state',
        input_schema: {
          type: 'object',
          properties: {
            filepath: { 
              type: 'string', 
              description: 'Path to file relative to repository root (e.g., "app/controllers/users_controller.rb")' 
            }
          },
          required: ['filepath']
        }
      },
      {
        name: 'analyze_log_statements',
        description: 'Extract and analyze all log statements (error, warn, info) from code changes to suggest log-based monitoring',
        input_schema: {
          type: 'object',
          properties: {
            file_content: {
              type: 'string',
              description: 'File content or code snippet to analyze for log statements'
            }
          },
          required: ['file_content']
        }
      },
      {
        name: 'find_dependent_code',
        description: 'Find code that depends on or calls the modified methods/classes to understand impact scope',
        input_schema: {
          type: 'object',
          properties: {
            class_name: {
              type: 'string',
              description: 'Class name to search for references (e.g., "UserController", "PaymentService")'
            },
            method_name: {
              type: 'string',
              description: 'Method name to search for (optional, e.g., "create", "process_payment")'
            }
          },
          required: ['class_name']
        }
      },
      {
        name: 'learn_from_existing_dashboards',
        description: 'Analyze existing NewRelic dashboards to understand current monitoring patterns and match style',
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
      },
      {
        name: 'query_newrelic',
        description: 'Execute a NRQL query against NewRelic to check existing monitoring or baseline metrics',
        input_schema: {
          type: 'object',
          properties: {
            nrql: { 
              type: 'string', 
              description: 'NRQL query to execute. MUST include appName filter using the name from get_newrelic_app_name tool.' 
            },
            account_id: {
              type: 'string',
              description: 'NewRelic account ID (optional, uses default if not provided)'
            }
          },
          required: ['nrql']
        }
      },
      {
        name: 'check_existing_infrastructure',
        description: 'Check if infrastructure.yml exists in the repository and read its current configuration',
        input_schema: {
          type: 'object',
          properties: {
            path: {
              type: 'string',
              description: 'Path to infrastructure file (default: "infrastructure.yml")',
              default: 'infrastructure.yml'
            }
          },
          required: []
        }
      },
      {
        name: 'create_temp_dashboard_files',
        description: 'Generate the structure for temporary dashboard files (reference and queries)',
        input_schema: {
          type: 'object',
          properties: {
            dashboard_name: { 
              type: 'string',
              description: 'Name for the dashboard (e.g., "pr-1234-api-monitoring")'
            },
            queries: { 
              type: 'array',
              description: 'Array of query objects with title and nrql fields',
              items: { 
                type: 'object',
                properties: {
                  title: { type: 'string' },
                  nrql: { type: 'string' },
                  description: { type: 'string' }
                }
              }
            },
            description: {
              type: 'string',
              description: 'Description of what this dashboard monitors'
            }
          },
          required: ['dashboard_name', 'queries']
        }
      },
      {
        name: 'suggest_permanent_config',
        description: 'Generate permanent infrastructure.yml configuration for long-term monitoring',
        input_schema: {
          type: 'object',
          properties: {
            config: { 
              type: 'object', 
              description: 'Infrastructure configuration following platform schema'
            },
            rationale: {
              type: 'string',
              description: 'Explanation of why this monitoring is needed'
            }
          },
          required: ['config']
        }
      }
    ]
  end
  
  def execute(tool_name, input)
    case tool_name
    when 'get_newrelic_app_name'
      get_newrelic_app_name(input['repo_name'])
    when 'get_pr_diff'
      get_pr_diff
    when 'analyze_file'
      analyze_file(input['filepath'])
    when 'analyze_log_statements'
      analyze_log_statements(input['file_content'])
    when 'find_dependent_code'
      find_dependent_code(input['class_name'], input['method_name'])
    when 'learn_from_existing_dashboards'
      learn_from_existing_dashboards(input['app_name'])
    when 'query_newrelic'
      query_newrelic(input['nrql'], input['account_id'])
    when 'check_existing_infrastructure'
      check_existing_infrastructure(input['path'] || 'infrastructure.yml')
    when 'create_temp_dashboard_files'
      create_temp_dashboard_files(
        input['dashboard_name'], 
        input['queries'],
        input['description']
      )
    when 'suggest_permanent_config'
      suggest_permanent_config(input['config'], input['rationale'])
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  rescue => e
    { 
      error: e.message,
      backtrace: e.backtrace.first(5)
    }
  end
  
  private
  
  # NEW TOOL: Detect correct NewRelic app name
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
                ... on ApmApplicationEntityOutline {
                  applicationId
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
      entities = response.body.dig('data', 'actor', 'entitySearch', 'results', 'entities') || []
      
      # Try exact match
      exact_match = entities.find { |e| e['name'].downcase == repo_name.downcase }
      if exact_match
        return {
          success: true,
          app_name: exact_match['name'],
          guid: exact_match['guid'],
          application_id: exact_match['applicationId'],
          match_type: 'exact'
        }
      end
      
      # Try fuzzy match (contains repo name)
      fuzzy_matches = entities.select { |e| e['name'].downcase.include?(repo_name.downcase) }
      
      if fuzzy_matches.length == 1
        match = fuzzy_matches.first
        return {
          success: true,
          app_name: match['name'],
          guid: match['guid'],
          application_id: match['applicationId'],
          match_type: 'fuzzy',
          confidence: 'high'
        }
      elsif fuzzy_matches.length > 1
        return {
          success: false,
          error: "Multiple matches found",
          suggestions: fuzzy_matches.map { |e| e['name'] },
          message: "Please manually specify which app to monitor. Add app name to repository description or use most relevant match."
        }
      else
        return {
          success: false,
          error: "No matching application found in NewRelic",
          searched_for: repo_name,
          available_apps: entities.map { |e| e['name'] }.first(10),
          message: "The repository name doesn't match any NewRelic application. Check if the app is reporting to NewRelic or use a different search term."
        }
      end
    else
      { 
        success: false,
        error: "NewRelic API error: #{response.status}",
        details: response.body 
      }
    end
  rescue => e
    { 
      success: false,
      error: "Failed to detect app name: #{e.message}",
      backtrace: e.backtrace.first(3)
    }
  end
  
  # NEW TOOL: Analyze log statements
  def analyze_log_statements(file_content)
    # Regex patterns for common logging in Ruby/Rails
    patterns = {
      error: [
        /(?:logger|Rails\.logger|log)\.error\s*[("']([^"']*)[)"']/,
        /raise\s+\w+Error[,\s]+[("']([^"']*)[)"']/
      ],
      warn: [
        /(?:logger|Rails\.logger|log)\.warn\s*[("']([^"']*)[)"']/
      ],
      info: [
        /(?:logger|Rails\.logger|log)\.info\s*[("']([^"']*)[)"']/
      ]
    }
    
    results = {
      error_logs: [],
      warn_logs: [],
      info_logs: [],
      monitoring_recommendations: []
    }
    
    file_content.each_line.with_index do |line, idx|
      patterns.each do |severity, pattern_list|
        pattern_list.each do |pattern|
          if match = line.match(pattern)
            log_entry = {
              line_number: idx + 1,
              message: match[1],
              context: line.strip,
              severity: severity
            }
            
            results[:"#{severity}_logs"] << log_entry
            
            # Generate monitoring recommendation for each log
            if severity == :error || severity == :warn
              results[:monitoring_recommendations] << {
                log_message: match[1],
                severity: severity,
                suggested_alert: {
                  name: "#{severity.to_s.capitalize}: #{match[1].slice(0, 50)}",
                  query: "SELECT count(*) FROM Log WHERE message LIKE '%#{match[1].gsub("'", "''")}%' SINCE 5 minutes ago",
                  threshold: severity == :error ? 5 : 20
                }
              }
            end
          end
        end
      end
    end
    
    results[:summary] = {
      total_errors: results[:error_logs].length,
      total_warnings: results[:warn_logs].length,
      total_info: results[:info_logs].length,
      requires_monitoring: results[:error_logs].any? || results[:warn_logs].any?
    }
    
    results
  rescue => e
    { error: "Failed to analyze log statements: #{e.message}" }
  end
  
  # NEW TOOL: Find dependent code
  def find_dependent_code(class_name, method_name = nil)
    # Search for references using GitHub's code search
    search_query = if method_name
      "#{class_name}.#{method_name} OR #{class_name}::#{method_name} repo:#{@repo}"
    else
      "#{class_name} repo:#{@repo}"
    end
    
    results = @github.search_code(search_query, per_page: 20)
    
    dependencies = results.items.map do |item|
      {
        file: item.path,
        url: item.html_url,
        repository: item.repository.full_name
      }
    end
    
    impact_level = assess_impact(results.total_count)
    
    {
      success: true,
      searched_for: method_name ? "#{class_name}.#{method_name}" : class_name,
      total_references: results.total_count,
      dependencies: dependencies.first(10),
      impact_assessment: impact_level,
      monitoring_priority: derive_priority(impact_level),
      recommended_monitors: [
        "Success rate of #{class_name}#{method_name ? ".#{method_name}" : ''}",
        "Response time percentiles",
        "Error rate by caller"
      ]
    }
  rescue Octokit::UnprocessableEntity => e
    {
      success: false,
      error: "GitHub code search failed - may be too many results or rate limited",
      message: "Assume HIGH impact and implement comprehensive monitoring",
      default_monitoring: [
        "End-to-end transaction success rate",
        "Error monitoring with detailed breakdown",
        "Performance monitoring across all callers"
      ]
    }
  rescue => e
    { 
      success: false,
      error: "Failed to find dependencies: #{e.message}",
      default_action: "Implement monitoring assuming medium-high impact"
    }
  end
  
  def assess_impact(reference_count)
    case reference_count
    when 0..5
      "Low - Few dependencies, localized impact. Basic monitoring sufficient."
    when 6..15
      "Medium - Moderate dependencies. Watch for cascade failures. Implement alert chains."
    when 16..50
      "High - Many dependencies. Critical to monitor end-to-end flow. Need comprehensive dashboards."
    when 51..Float::INFINITY
      "Critical - Heavily used component. Failure will cascade widely. Requires SLO tracking and multi-level alerts."
    end
  end
  
  def derive_priority(impact_level)
    if impact_level.start_with?("Critical") || impact_level.start_with?("High")
      "P0 - Must have monitoring before merge"
    elsif impact_level.start_with?("Medium")
      "P1 - Should have monitoring in same sprint"
    else
      "P2 - Nice to have, can be added incrementally"
    end
  end
  
  # NEW TOOL: Learn from existing dashboards
  def learn_from_existing_dashboards(app_name)
    # Query for existing dashboards
    graphql_query = <<~GRAPHQL
      {
        actor {
          entitySearch(query: "domain = 'VIZ' AND type = 'DASHBOARD'") {
            results {
              entities {
                name
                guid
                ... on DashboardEntityOutline {
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
      
      # Filter for relevant dashboards (containing app name or common terms)
      relevant_dashboards = dashboards.select do |d|
        name_lower = d['name'].downcase
        name_lower.include?(app_name.downcase) || 
        name_lower.include?('api') ||
        name_lower.include?('service') ||
        name_lower.include?('application')
      end
      
      patterns = extract_common_patterns(relevant_dashboards)
      
      {
        success: true,
        total_dashboards_found: relevant_dashboards.length,
        dashboards: relevant_dashboards.first(5).map { |d| { name: d['name'], guid: d['guid'] } },
        common_patterns: patterns,
        style_recommendations: derive_style_recommendations(patterns),
        gaps_identified: identify_monitoring_gaps(patterns)
      }
    else
      { 
        success: false,
        error: "Failed to fetch dashboards: #{response.status}",
        default_action: "Use standard monitoring patterns from documentation"
      }
    end
  rescue => e
    { 
      success: false,
      error: "Failed to learn from dashboards: #{e.message}",
      default_action: "Proceed with standard monitoring recommendations"
    }
  end
  
  def extract_common_patterns(dashboards)
    {
      has_error_monitoring: dashboards.any? { |d| d['name'].match?(/error|exception|failure/i) },
      has_performance_monitoring: dashboards.any? { |d| d['name'].match?(/performance|latency|response/i) },
      has_business_metrics: dashboards.any? { |d| d['name'].match?(/business|revenue|conversion|user/i) },
      has_infrastructure: dashboards.any? { |d| d['name'].match?(/infra|system|resource|health/i) },
      has_api_monitoring: dashboards.any? { |d| d['name'].match?(/api|endpoint|request/i) },
      total_dashboard_count: dashboards.length
    }
  end
  
  def derive_style_recommendations(patterns)
    recommendations = []
    
    recommendations << "Follow existing error monitoring patterns" if patterns[:has_error_monitoring]
    recommendations << "Match existing performance dashboard style" if patterns[:has_performance_monitoring]
    recommendations << "Include business impact metrics (user-facing)" if patterns[:has_business_metrics]
    recommendations << "Add infrastructure health checks" if patterns[:has_infrastructure]
    recommendations << "Use API-centric dashboard layout" if patterns[:has_api_monitoring]
    
    recommendations << "Establish baseline dashboard standards" if recommendations.empty?
    
    recommendations
  end
  
  def identify_monitoring_gaps(patterns)
    gaps = []
    
    gaps << "No error monitoring found - HIGH PRIORITY to add" unless patterns[:has_error_monitoring]
    gaps << "No performance monitoring - add latency tracking" unless patterns[:has_performance_monitoring]
    gaps << "Missing business metrics - consider adding user impact" unless patterns[:has_business_metrics]
    gaps << "No infrastructure monitoring - add health checks" unless patterns[:has_infrastructure]
    
    gaps << "Monitoring coverage looks good!" if gaps.empty?
    
    gaps
  end
  
  # EXISTING TOOLS (unchanged)
  
  def get_pr_diff
    files = @github.pull_request_files(@repo, @pr_number)
    
    result = {
      total_files: files.length,
      files: files.map do |f|
        {
          filename: f.filename,
          status: f.status,
          additions: f.additions,
          deletions: f.deletions,
          changes: f.changes,
          patch: f.patch || 'Binary file or no changes'
        }
      end
    }
    
    result
  rescue => e
    { error: "Failed to fetch PR diff: #{e.message}" }
  end
  
  def analyze_file(filepath)
    content = @github.contents(@repo, path: filepath)
    decoded_content = Base64.decode64(content.content)
    
    {
      filepath: filepath,
      size: content.size,
      content: decoded_content,
      encoding: content.encoding
    }
  rescue Octokit::NotFound
    { error: "File not found: #{filepath}" }
  rescue => e
    { error: "Failed to read file: #{e.message}" }
  end
  
  def query_newrelic(nrql, account_id = nil)
    # NewRelic NerdGraph API
    conn = Faraday.new(url: 'https://api.newrelic.com/graphql') do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
    
    graphql_query = <<~GRAPHQL
      {
        actor {
          nrql(query: "#{nrql.gsub('"', '\\"')}") {
            results
          }
        }
      }
    GRAPHQL
    
    response = conn.post do |req|
      req.headers['API-Key'] = @nr_key
      req.headers['Content-Type'] = 'application/json'
      req.body = { query: graphql_query }
    end
    
    if response.success?
      response.body
    else
      { error: "NewRelic API error: #{response.status} - #{response.body}" }
    end
  rescue => e
    { error: "Failed to query NewRelic: #{e.message}" }
  end
  
  def check_existing_infrastructure(path = 'infrastructure.yml')
    begin
      file = @github.contents(@repo, path: path)
      content = Base64.decode64(file.content)
      
      {
        exists: true,
        path: path,
        content: content,
        size: file.size
      }
    rescue Octokit::NotFound
      {
        exists: false,
        path: path,
        message: "infrastructure.yml not found in repository root"
      }
    end
  rescue => e
    { error: "Failed to check infrastructure file: #{e.message}" }
  end
  
  def create_temp_dashboard_files(dashboard_name, queries, description = nil)
    # Generate the reference file content
    reference_content = generate_temp_reference(dashboard_name, description)
    
    # Generate the queries file content
    queries_content = format_queries(queries)
    
    {
      success: true,
      files: {
        reference_file: {
          path: "temp/#{dashboard_name}.yml",
          content: reference_content
        },
        queries_file: {
          path: "temp/#{dashboard_name}-queries.nrql",
          content: queries_content
        }
      },
      instructions: "Add these files to your repository and reference them in infrastructure.yml"
    }
  rescue => e
    { error: "Failed to generate dashboard files: #{e.message}" }
  end
  
  def suggest_permanent_config(config, rationale = nil)
    # Format the configuration as YAML
    require 'yaml'
    
    formatted_config = config.to_yaml
    
    result = {
      success: true,
      config: formatted_config,
      rationale: rationale,
      instructions: "Add this configuration to your infrastructure.yml file"
    }
    
    result
  rescue => e
    { error: "Failed to format config: #{e.message}" }
  end
  
  def generate_temp_reference(name, description)
    <<~YAML
      # Temporary dashboard for PR monitoring
      # Auto-expires 7 days after merge
      temp_dashboards:
        - name: #{name}
          queries_file: temp/#{name}-queries.nrql
          expires_after: 7_days
          description: "#{description || 'Monitoring for PR changes'}"
    YAML
  end
  
  def format_queries(queries)
    queries.map.with_index do |q, i|
      <<~NRQL
        -- Query #{i + 1}: #{q['title']}
        -- #{q['description'] || 'No description'}
        #{q['nrql']}
        
      NRQL
    end.join("\n")
  end
end
