# encoding: utf-8

require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "open-uri"
require "rufus/scheduler"
require "open3"

class LogStash::Filters::CloudFoundry < LogStash::Filters::Base

  config_name "cloudfoundry"

  config :cf_api,              		   :validate => :string 								        # Cloud Foundry API endpoing
  config :cf_user,             		   :validate => :string	  					         		# Users Cloud Foundry username
  config :cf_password,         		   :validate => :string 	 							        # Users Cloud Foundry password
  config :cf_org,         		       :validate => :string   			                # An org that a user has access to with their account
  config :cf_space,       		       :validate => :string       	                # A space that a user has access to with their account
  config :skip_ssl_validation, 		   :validate => :boolean, :default => true			# Skip SSL validation while loging into the endpoint (true/false)

  config :cache_flush_time,    		   :validate => :string,  :default => "10m"		  # How often the cache is cleaned out
  config :cache_age_time,      		   :validate => :number,  :default => 600				# An items expiration date in the cache

  config :cf_retry_cli_timeout,	   	 :validate => :number,  :default => 0   		  # If set to 0, if a cf cli command fails it will retry on the next log

  public
  def register

    if @cf_api.empty? || @cf_user.empty? || @cf_password.empty? || @cf_org.empty || @cf_space.empty
      raise "CF-invalid-parameters" unless cflogin[:status]

      #raise RuntimeError.new(
      #    "Cannot specify queue parameter and key or data_type"
      #)
    end

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

    @cf_retry_cli_timeout > 0 ? @cf_retry_cli = true : @cf_retry_cli = false
    @login_next = Time.now.to_i
    @cf_logged_in = true

  rescue Exception => e

    if e.inspect.include?("CF-login-Failed") || e.inspect.include?("CF-invalid-parameters")
      @cf_retry_cli = false
      @cf_logged_in = false
    end
    @logger.error("Exception: #{e.inspect}. Filter won't be applied")
    @logger.error("Backtrace: #{e.backtrace}")

  end # def register

  public
  def filter(event)

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

          app_info = Hash.new()
          app_info["appname"]   = app_query[:stdout]["entity"]["name"]
          app_info["spacename"] = space_query[:stdout]["entity"]["name"]
          app_info["orgname"]   = org_query[:stdout]["entity"]["name"]

          app_cache_item = Hash.new()
          app_cache_item["info"]      = app_info
          app_cache_item["expire_at"] = Time.now.to_i + @cache_age_time

          @app_cache_mutex.synchronize { @app_cache[app_guid] = app_cache_item }
        else
          app_info = app_cache_item['info']
        end
        app_info.each { |k,v| event[k] = v }
      end

    else

      if @login_next <= Time.now.to_i && @cf_retry_cli
        raise "CF-login-Failed" unless cflogin[:status]
        @cf_logged_in = true
      end

    end

    filter_matched(event)

  rescue Exception => e

    if e.inspect.include?("CF-Invalid-AppGUID")
      @logger.error("Exception: The following GUID was invalid: #{event["appguid"]}")
    elsif e.inspect.include?("CF-curl-Failed") || e.inspect.include?("CF-login-Failed")
      @logger.error("Exception: #{e.inspect}.")
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
      ' -o ' + @cf_org +
      ' -s ' + @cf_space )

  end

  private
  def cf(cmd)

    stdout, stderr, status = Open3.capture3("cf #{cmd}")
    command_output = { :stdout => valid_json?(stdout), :stderr => stderr, :status => status.success?}
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
