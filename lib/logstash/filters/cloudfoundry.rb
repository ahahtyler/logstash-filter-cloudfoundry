require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "open-uri"
require "rufus/scheduler"
require "open3"

class LogStash::Filters::Foo < LogStash::Filters::Base

  config_name "cloudfoundry"

  config :cf_api,              		   :validate => :string									# Cloud Foundry API endpoing
  config :cf_user,             		   :validate => :string									# Users Cloud Foundry username
  config :cf_password,         		   :validate => :string									# Users Cloud Foundry password
  config :default_org,         		   :validate => :string,  :default => "system"			# An org that a user has access to with their account
  config :default_space,       		   :validate => :string,  :default => "apps-manager"	# A space that a user has access to with their account 
  config :skip_ssl_validation, 		   :validate => :boolean, :default => true				# Skip SSL validation while loging into the endpoint (true/false)
  config :cache_flush_time,    		   :validate => :string,  :default => "10m"				# How often the cache is cleaned out
  config :cache_age_time,      		   :validate => :number,  :default => 600				# An items expiration date in the cache
  config :cf_cli_timeout, 	   		   :validate => :number,  :default => 0   				# If set to 0, the cf cli command will be executed without the timeout command
																							# If set to x, the execution of the cf cli command will be killed after that time period
  config :cf_retry_cli_timeout,	   	   :validate => :number,  :default => 0   				# If set to 0, if a cf cli command fails it will retry on the next log
																							# If set to x, if a cf cli command fails it will wait x seconds before retrying
  config :cf_retry_cli,				   :validate => :boolean, :default => false			    # Should I continue to hit the CF endpoint if a single command fails? 
  
  public
  def register
  
    if @cf_api.empty? || @cf_user.empty? || @cf_password.empty?
	  @cf_retry_cli = false
      @cf_logged_in = false
	  @logger.warn("Requirement parameters where not passed in. Filter won't be applied.")
	else
      @app_cache       = Hash.new
      @app_cache_mutex = Mutex.new
      @scheduler       = Rufus::Scheduler.new
      @job = @scheduler.every(@cache_flush_time) do
        begin
          @app_cache_mutex.synchronize {
            @app_cache.delete_if { |key, value| value["expire_at"]<Time.now.to_i }
          }
        rescue Exception => msg
          @logger.error("Error purging app info cache: #{msg}")
        end
      end
	  
	  raise "CF-login-Failed" unless cflogin[:status]
	  @cf_logged_in = true 
	 
    end
		
  rescue Exception => e
  
    @logger.error("Error in initialization of filter. Filter won't be applied. ")
	
	if e.inspect.include?("CF-login-Failed")
	  @logger.error("Exception: The CF login command failed to execute.")
	  @cf_retry_cli = false
	  @cf_logged_in = false
	else
	  @logger.error("Exception: #{e.inspect}")
	end
	
	@logger.error("Backtrace: #{e.backtrace}")
	
  end # def register
  
  public
  def filter(event)

  #TODO: What if I've been given a bad guid?
  
  if @cf_logged_in

      message = event["message"]
      app_guid = message[/loggregator ([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/, 1]

      unless app_guid.nil?
	  
        event["appguid"] = app_guid
        app_cache_item = nil
        @app_cache_mutex.synchronize { app_cache_item = @app_cache[app_guid] }

        if app_cache_item.nil?
		
          app_query   = cfcurl("/v2/apps/#{app_guid}")
		  validate_app_query(app_query, app_guid)		  
          raise "CF-curl-Failed" unless app_query[:status]

          space_query = cfcurl("/v2/spaces/#{app_query[:stdout]["entity"]["space_guid"]}")
          raise "CF-curl-Failed" unless space_query[:status]

          org_query   = cfcurl("/v2/organizations/#{space_query[:stdout]["entity"]["organization_guid"]}")
          raise "CF-curl-Failed" unless org_query[:status]

          app_info              = Hash.new()
          app_info["appname"]   = app_query[:stdout]["entity"]["name"]
          app_info["spacename"] = space_query[:stdout]["entity"]["name"]
          app_info["orgname"]   = org_query[:stdout]["entity"]["name"]

          app_cache_item              = Hash.new()
          app_cache_item["expire_at"] = Time.now.to_i + @cache_age_time
          app_cache_item["info"]      = app_info

          @app_cache_mutex.synchronize { @app_cache[app_guid] = app_cache_item }
        else
          app_info = app_cache_item['info']
        end
        app_info.each { |k,v| event[k] = v }
      end
    else
	
      @login_next = Time.now.to_i if @login_next.nil?
      if @login_next <= Time.now.to_i && @cf_retry_cli
        raise "CF-login-Failed" unless cflogin[:status]
        @cf_logged_in = true
      end
    end

    filter_matched(event)

  rescue Exception => e

	if e.inspect.include?("CF-Invalid-AppGUID")
	  @logger.error("Exception: The following GUID was invalid: #{event["appguid"]}")
	elsif e.inspect.include?("CF-curl-Failed")
	  @logger.error("Exception: The CF CURL command failed to execute.")
	  @cf_logged_in = false
      @login_next = Time.now.to_i + @cf_retry_cli_timeout
	elsif e.inspect.include?("CF-login-Failed")
	  @logger.error("Exception: The CF login command failed to execute.")
	  @cf_logged_in = false
      @login_next = Time.now.to_i + @cf_retry_cli_timeout
	else
	  @logger.error("Exception: #{e.inspect}")
	end
	
	@logger.error("Backtrace: #{e.backtrace}")
	
  end

  private
  def validate_app_query(app_query, app_guid)
  
	if app_query[:status]
	
	  unless app_query[:stdout]['error_code'].nil?
		  if app_query[:stdout]['error_code'].include?("CF-AppNotFound")

			  app_cache_item              = Hash.new()
			  app_cache_item["expire_at"] = Time.now.to_i + @cache_age_time
			  app_cache_item["info"]      = {}

			  @app_cache_mutex.synchronize { @app_cache[app_guid] = app_cache_item }
			  raise "CF-Invalid-AppGUID"
		  end
	  end
	end
	
  end
  
  private
  def cfcurl(path, body = nil)
  
    if body.nil?
      cf('curl ' + URI::encode(path))
    else
      cf('curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"')
    end

  end

  private
  def cflogin

    cf( 'login' +
      (@skip_ssl_validation ? ' --skip-ssl-validation' : '') +
      ' -a ' + @cf_api + 
      ' -u ' + @cf_user + 
      ' -p ' + @cf_password + 
      ' -o ' + @default_org + 
      ' -s ' + @default_space )
   
  end

  private
  def cf(cmd)
	
    stdout, stderr, status = Open3.capture3("timeout #{@cf_cli_timeout} cf #{cmd}")
    command_output = { :stdout => valid_json?(stdout), :stderr => stderr, :status => status.success?}

    if stdout.include?("Error finding org") || stdout.include?("Error finding space")
      command_output[:status] = true
    end
		
    command_output

  end

  private
  def valid_json?(stdout)
  
	begin
	  JSON.parse(stdout)
	rescue Exception => e
	  stdout
	end
	
  end
  
end
