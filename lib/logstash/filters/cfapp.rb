# Call this file 'foo.rb' (in logstash/filters, as above)
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require 'open-uri'

class LogStash::Filters::Foo < LogStash::Filters::Base

  # Setting the config_name here is required. This is how you
  # configure this filter from your logstash config.
  #
  # filter {
  #   foo { ... }
  # }
  config_name "cfapp"

  # New plugins should start life at milestone 1.
  milestone 1

  # How often to scan app info cache to remove expired items
  #
  # See the Rufus Scheduler docs for an [explanation of allowed values](https://github.com/jmettraux/rufus-scheduler#the-time-strings-understood-by-rufus-scheduler)
  config :cache_purge_interval, :validate => :string, :default => "10m"

  # Cache age in seconds
  config :cache_age_time, :validate => :number, :default => 600

  # CF API
  config :cfapi, :validate => :string

  # CF User
  config :cfuser, :validate => :string

  # CF Password
  config :cfpassword, :validate => :string

  # CF Password
  config :default_org, :validate => :string

  # CF Password
  config :default_space, :validate => :string

  # Skip certificate validation
  config :skip_ssl_validation, :validate => :boolean, :default => true

  public
  def register

    require "rufus/scheduler"

    if @cfapi.nil? ||
      @cfuser.nil? ||
      @cfpassword.nil? ||
      @default_org.nil? ||
      @default_space.nil?

      @logger.warn( "The filter arguments 'cfapi', 'cfuser', 'cfpassword', 'default_org' and 'default_space' are required. " +
        "CloudFoundry syslog filter will not be applied to events." )

      @cf_logged_in = false
    else
      cflogin

      @app_cache = Hash.new
      @app_cache_mutex = Mutex.new

      @scheduler = Rufus::Scheduler.new
      @job = @scheduler.every(@cache_purge_interval) do

        begin
          @app_cache_mutex.synchronize {
              @app_cache.delete_if { |key, value| value["expire_at"]<Time.now.to_i }
          }
        rescue Exception => msg
          @logger.error("Error purging app info cache: #{msg}")
        end
      end

      @logger.debug("Logged into CloudFoundry target '#{@cfapi}'. CloudFoundry syslog filter will be applied to events.")
      @cf_logged_in = true
    end

  rescue Exception => msg

    @logger.error("Error logging into CloudFoundry target '#{@cfapi}': #{msg}. " + 
      "CloudFoundry syslog filter will not be applied to events.")

    @cf_logged_in = true
  end

  public
  def filter(event)

    # return nothing unless there's an actual filter event or logged into cf
    return unless filter?(event)

    if @cf_logged_in

      message = event["message"]

      app_guid = message[/loggregator ([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/, 1]
      if app_guid.nil?
        event["appguid"] = "AppGuidNotFound"
      else
        event["appguid"] = app_guid

        app_cache_item = nil
        @app_cache_mutex.synchronize { app_cache_item = @app_cache[app_guid] }

        if app_cache_item.nil?

          app_query = cfcurl("/v2/apps/#{app_guid}")
          app_detail = app_query["entity"]
		  
          if app_detail.nil?
			
			#Try to log in again
			cflogin
			app_query = cfcurl("/v2/apps/#{app_guid}")
			app_detail = app_query["entity"]
			
			if app_detail.nil?
				#Mark appguid as unknown and return
				event["appguid"] = "#{app_guid}-UNKNOWN"
				filter_matched(event)
				return
			end
          end

          space_query = cfcurl("/v2/spaces/#{app_detail["space_guid"]}")
          org_query = cfcurl("/v2/organizations/#{space_query["entity"]["organization_guid"]}")

          app_info = { }
          app_info["appname"] = app_detail["name"]
          app_info["spacename"] = space_query["entity"]["name"]
          app_info["orgname"] = org_query["entity"]["name"]

          app_cache_item = { }
          app_cache_item["expire_at"] = Time.now.to_i + @cache_age_time
          app_cache_item["info"] = app_info
          @app_cache_mutex.synchronize { @app_cache[app_guid] = app_cache_item }
        else
          app_info = app_cache_item['info']
        end

        @logger.debug("cloudfoundry app info: #{app_info}")
        app_info.each { |k,v| event[k] = v }
      end
    end

    # filter_matched should go in the last line of our successful code 
    filter_matched(event)
  end

  private
  def cfcurl(path, body = nil)
    JSON.parse(
      body.nil? ? cf('curl ' + URI::encode(path)) 
      : cf('curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"') )
  end

  private
  def cflogin

    cf( 'login' +
      (@skip_ssl_validation ? ' --skip-ssl-validation' : '') +
      ' -a ' + @cfapi + 
      ' -u ' + @cfuser + 
      ' -p ' + @cfpassword + 
      ' -o ' + @default_org + 
      ' -s ' + @default_space )
  end

  private
  def cf(cmd)

    result = `cf #{cmd}`
    if !$?.success? && result[/Not logged in/]

      @logger.debug("Not logged in so retrying command after re-login.")

      cflogin
      result = `cf #{cmd}`
    end

    raise "Failed to execute bosh command: cf #{cmd} => #{result}" if !$?.success?
    result
  end

end
