# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require 'open-uri'


class LogStash::Filters::Example < LogStash::Filters::Base


  config_name "cloudfoundry"

  config :cf_api,              :validate => :string
  config :cf_user,             :validate => :string
  config :cf_password,         :validate => :string
  config :default_org,         :validate => :string,  :default => "system"
  config :default_space,       :validate => :string,  :default => "appsmanager"
  config :skip_ssl_validation, :validate => :boolean, :default => true
  config :cache_flush_time,    :validate => :string,  :default => "10m"
  config :cache_age_time,      :validate => :number,  :default => 600

  public
  def register
    require "rufus/scheduler"

    if @cf_api.empty? || @cf_user.empty? || @cf_password.empty?
      @logger.warn("Requirement parameters where not passed in. Filter won't be applied")
      @cf_logged_in = false
    else
      @cache       = Hash.new
      @cache_mutex = Mutex.new
      @scheduler   = Rufus::Scheduler.new

      @job = @scheduler.every(@cache_flush_time) do
        begin
          @app_cache_mutex.synchronize {
            @app_cache.delete_if { |key, value| value["expire_at"]<Time.now.to_i }
          }
        rescue Exception => e
          @logger.error("Error purging app info cache: #{e}")
        end
      end

      if cloudfoundry_login
        @logger.debug("Logged into CloudFoundry. Filter will be applied")
        @cf_logged_in = true
      else
        @logger.debug("Unable to log into Cloud Foundry. Filter will not be applied")
        @cf_logged_in = false
      end
    end

  rescue Exception => e
    @logger.error("Error logging into CloudFoundry. Filter won't be applied")
    @cf_logged_in = false
  end # def register

  public
  def filter(event)
    #TODO: Not sure if needed
    #return unless filter?(event)
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

          app_query = cloudfoundry_curl("/v2/apps/#{app_guid}")
          app_detail = app_query["entity"]

          if app_detail.nil?

            #Try to log in again
            cloudfoundry_login
            app_query = cfcurl("/v2/apps/#{app_guid}")
            app_detail = app_query["entity"]

            if app_detail.nil?
              #Mark appguid as unknown and return
              event["appguid"] = "unknown"
              filter_matched(event)
              return
            end
          end

          space_query = cloudfoundry_curl("/v2/spaces/#{app_detail["space_guid"]}")
          org_query = cloudfoundry_curl("/v2/organizations/#{space_query["entity"]["organization_guid"]}")

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

  end # def filter

  private
  def cloudfoundry_login
    cli_command = 'cf login' +
                  ' -a '     + @cf_api  +
                  ' -u '     + @cf_user +
                  ' -p '     + @cf_password +
                  ' -o '     + @default_org +
                  ' -s '     + @default_space +
                 (@skip_ssl_validation ? ' --skip-ssl-validation' : '')
    result = `#{cli_command}`
    #TODO: Look at this again. It's not correct for this approach
    return !(!$?.success? && result[/Not logged in/])
  end

  def cloudfoundry_curl(path, body = nil)
    if body.nil?
      cli_command = 'cf curl ' + URI::encode(path)
    else
      cli_command = 'cf curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"'
    end
    return `#{cli_command}`
  end

end # class LogStash::Filters::Example