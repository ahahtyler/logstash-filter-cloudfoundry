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
  config :default_space,       :validate => :string,  :default => "development"
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

   if @cf_logged_in

   else
     #try to log in again
   end

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
      cf('curl ' + URI::encode(path))
    else
      cf('curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"')
    end
  end

end # class LogStash::Filters::Example