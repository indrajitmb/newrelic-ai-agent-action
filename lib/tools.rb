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
        name: 'query_newrelic',
        description: 'Execute a NRQL query against NewRelic to check existing monitoring or baseline metrics',
        input_schema: {
          type: 'object',
          properties: {
            nrql: { 
              type: 'string', 
              description: 'NRQL query to execute (e.g., "SELECT count(*) FROM Transaction WHERE appName = \'frederick\' SINCE 1 day ago")' 
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
    when 'get_pr_diff'
      get_pr_diff
    when 'analyze_file'
      analyze_file(input['filepath'])
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

