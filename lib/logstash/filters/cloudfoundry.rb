# Call this file 'foo.rb' (in logstash/filters, as above)
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "open-uri"
require "rufus/scheduler"
require "open3"

class LogStash::Filters::Foo < LogStash::Filters::Base

  config_name "cloudfoundry"

  config :cf_api,              :validate => :string
  config :cf_user,             :validate => :string
  config :cf_password,         :validate => :string
  config :default_org,         :validate => :string,  :default => "system"
  config :default_space,       :validate => :string,  :default => "apps-manager"
  config :skip_ssl_validation, :validate => :boolean, :default => true
  config :cache_flush_time,    :validate => :string,  :default => "10m"
  config :cache_age_time,      :validate => :number,  :default => 600

  public
  def register
    if @cf_api.empty? || @cf_user.empty? || @cf_password.empty?
      @logger.warn("Requirement parameters where not passed in. Filter won't be applied")
      @cf_logged_in = false
    else
       @app_cache = Hash.new
       @app_cache_mutex = Mutex.new
       @scheduler = Rufus::Scheduler.new

	    @job = @scheduler.every(@cache_flush_time) do
        begin
          @app_cache_mutex.synchronize {
              @app_cache.delete_if { |key, value| value["expire_at"]<Time.now.to_i }
          }
        rescue Exception => msg
          @logger.error("Error purging app info cache: #{msg}")
        end
      end

	    login_status, login_output = cflogin
	  
      if login_status
        @logger.warn("Logged into CloudFoundry. Filter will be applied")
        @cf_logged_in = true
      else
        @logger.error("Unable to log into Cloud Foundry. Filter will not be applied")
        @cf_logged_in = false
      end
    end
  rescue Exception => e
    @logger.error("Error logging into CloudFoundry. Filter won't be applied")
    @logger.error("Exception: #{e.inspect}")
    @logger.error("Backtrace: #{e.backtrace}")
    @cf_logged_in = false
  end # def register
  
  public
  def filter(event)

    @logger.warn("CF LOGGED IN FLAG IS: #{@cf_logged_in}")

    if @cf_logged_in
      message = event["message"]
      @logger.warn("CF EVENT MESSAGE IS: #{message}")
      app_guid = message[/loggregator ([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/, 1]

      #If there's no app guid don't parse the request further
      @logger.warn("CF APPGUID IS:  #{app_guid}")

      if app_guid.nil?
        @logger.warn("No GUID was detected, log will not be processed")
      else
        event["appguid"] = app_guid

        app_cache_item = nil
        @app_cache_mutex.synchronize { app_cache_item = @app_cache[app_guid] }

        if app_cache_item.nil?
          @logger.warn("GUID IS NOT IN CACHE")
          app_query_status, app_query = cfcurl("/v2/apps/#{app_guid}")

          @logger.warn("CF app_query_status: #{app_query_status}")
          @logger.warn("CF app_query: #{app_query}")

          app_detail = app_query["entity"]
          #TODO: What should I do if query_status is false?

          space_query_status, space_query = cfcurl("/v2/spaces/#{app_detail["space_guid"]}")
          #TODO: What should I do if query_status is false?

          org_query_status, org_query = cfcurl("/v2/organizations/#{space_query["entity"]["organization_guid"]}")
          #TODO: What should I do if query_status is false?

          app_info = { }
          app_info["appname"] = app_detail["name"]
          app_info["spacename"] = space_query["entity"]["name"]
          app_info["orgname"] = org_query["entity"]["name"]

          app_cache_item = { }
          app_cache_item["expire_at"] = Time.now.to_i + @cache_age_time
          app_cache_item["info"] = app_info
          @app_cache_mutex.synchronize { @app_cache[app_guid] = app_cache_item }

        else
          @logger.warn("GUID IS IN CACHE")
          app_info = app_cache_item['info']
        end

        @logger.debug("cloudfoundry app info: #{app_info}")
        app_info.each { |k,v| event[k] = v }
      end
    else
      @logger.warn("No longer logged in. Maybe I should do something about it")
      #TODO: What should I do if I'm no longer logged in
    end

    filter_matched(event)
  rescue Exception => e
    @logger.error("Exception message: #{e.inspect}")
    @logger.error("Exception backtrace: #{e.backtrace}")
  end

  private
  def cfcurl(path, body = nil)
    if body.nil?
      curl_status, curl_body = cf('curl ' + URI::encode(path))
    else
      curl_status, curl_body = cf('curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"')
    end
    return curl_status, JSON.parse(curl_body)
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
  def cflogout
    cf ( 'logout' )
  end
  
  private
  def cf(cmd)
	
    @logger.warn("Executing the following command ' cf #{cmd}'")
    stdout, stderr, status = Open3.capture3("timeout 10 cf #{cmd}")

    @logger.warn("PRINT - -----------------------------")
    @logger.warn("PRINT - CF Command stdout: #{stdout}")
    @logger.warn("PRINT - -----------------------------")
    @logger.warn("PRINT - CF Command stderr: #{stderr}")
    @logger.warn("PRINT - -----------------------------")
    @logger.warn("PRINT - CF Command status: #{status.success?}")
    @logger.warn("PRINT - -----------------------------")

    return_status = status.success?

    unless status.success?
      @logger.warn("CF command failed")
      if stdout.include?("Error finding org")
        return_status = true
        @logger.warn("An invalid org was submitted but processesing will continue")
      elsif stdout.include?("Error finding space")
        return_status = true
        @logger.warn("An invalid space was submitted but processing will continue ")
      else
        return_status = false
        @logger.error("Unable to complete command 'cf #{cmd}")
        @logger.error("Following output was generated: #{stdout}")
      end
    end

    return return_status, stdout

  end

end