# encoding: utf-8

require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "open-uri"
require "rufus/scheduler"
require "open3"


# The Cloud Foundry filter performs a lookup against a Cloud Foundry foundation to provide the following pieces of
# meta-data to an application log
#  - Org name
#  - Space name
#  - Application name
#
#The conf should look like this:
#   filter{
#     cloudfoundry{
#         cf_api      => "https://api.cf-domain.com"
#         cf_user     => username
#         cf_password => password
#         cf_org      => "system"
#         cf_space    => "apps_manager"
#     }
#   }
#
# For this plugin to work you will need the CF CLI installed on your system. (https://github.com/cloudfoundry/cli)
#
# This filter only processes 1 event at a time so the use of this plugin can significantly slow down your pipeline's
# throughput if you have a high latency network. In the event of an outage (network or cloud foundry infrastructure), a
# retry flag can bet set to reduce the number of failed log-in and curl attempts to the Cloud Foundry endpoint. This
# will allow the pipeline to function without severely impacting throughput. Additionally adjusting the cache flush
# period and a cache items TTL will reduce slow down to your pipeline's throughput at the cost of additional resource
# consumption.
#
# To set up receiving logs from multiple foundations the user executing logstash will need write premissions to it's
# home directiory. To achieve connecting to multiple CF endpoints at once the CF_HOME variable needs to be a unique
# path for each initialization of the plugin. The configuration should look similar to the following: 
#
#   filter{
#     if "zone1" in [tags]
#         cloudfoundry{
#             cf_api      => "https://api.cf-domain1.com"
#             ....
#         }
#     }
#     if "zone2" in [tags]
#         cloudfoundry{
#             cf_api      => "https://api.cf-domain2.com"
#             ....
#         }
#     }
#   }
#
#

class LogStash::Filters::CloudFoundry < LogStash::Filters::Base
  #TODO: Pull "log-type" field from raw Cloud Foundry log
  #TODO: Determine windows equivalent of a linux "timeout" command to improve pipeline throughput during an outage

  config_name "cloudfoundry"

  # Cloud Foundry API endpoing
  config :cf_api,              		   :validate => :string

  # Users Cloud Foundry username
  config :cf_user,             		   :validate => :string

  # Users Cloud Foundry password
  config :cf_password,         		   :validate => :string

  # Any Cloud Foundry Org that a users account has access to
  config :cf_org,         		       :validate => :string

  # Any Cloud Foundry Space that a users account has access to
  config :cf_space,       		       :validate => :string

  # Skip SSL validation while logging into the endpoint
  config :skip_ssl_validation, 		   :validate => :boolean, :default => true

  # How often the scheduler is run to clean up cache
  config :cache_flush_time,    		   :validate => :string,  :default => "10m"

  # A cache items time to live
  config :cache_age_time,      		   :validate => :number,  :default => 600

  # After a failed attempt to reach the Cloud Foundry endpoint, how long should the plugin wait before using the cf CLI again
  config :cf_retry_cli_timeout,	      :validate => :number,  :default => 0

  # If the the Cloud Foundry API can not find GUID, cache it so plugin won't waste resouces continuously curling it 
  config :cache_invalid_guids, 		  :validate => :boolean, :default => false
  
  public
  def register

    #Check input
    if @cf_api.empty? || @cf_user.empty? || @cf_password.empty? || @cf_org.empty? || @cf_space.empty?
      raise "Required paramters where left blank."
    end
	
    #Set up cache and scheduler
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

    #define CF_HOME path
    @cf_path = "#{ENV['HOME']}/#{@cf_api.gsub(/[^0-9A-Za-z]/, '')}"	
    stdout, stderr, status = Open3.capture3("mkdir #{@cf_path}")	
	
    #Check folder creation status. 
    unless status.success?
      unless stderr.include?("File exists")
        raise "CF-Home-Folder-Creation: #{stderr}"
      end
    end

    #Login to CF endpoint
    login_query = cflogin
    raise "CF-login-failed: #{login_query[:stdout]}" unless login_query[:status]

    @cf_retry_cli_timeout > 0 ? @cf_retry_cli = true : @cf_retry_cli = false
    @login_next = Time.now.to_i
    @cf_logged_in = true
	
  rescue Exception => e

    @cf_retry_cli = false
    @cf_logged_in = false
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
          validate_query(app_query, app_guid)

          space_query = cfcurl("/v2/spaces/#{app_query[:stdout]["entity"]["space_guid"]}")
          validate_query(space_query)

          org_query   = cfcurl("/v2/organizations/#{space_query[:stdout]["entity"]["organization_guid"]}")
          validate_query(org_query)

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
        login_query = cflogin
        raise "CF-login-failed: #{login_query[:stdout]}" unless login_query[:status]
        @cf_logged_in = true
      end

    end

    filter_matched(event)

  rescue Exception => e

    if e.inspect.include?("CF-curl-failed") || e.inspect.include?("CF-login-failed")
      @logger.error("Exception: #{e.inspect}.")
      @login_next   = Time.now.to_i + @cf_retry_cli_timeout
      @cf_logged_in = false
    else
      @logger.error("Exception: #{e.inspect}")
    end
    @logger.error("Backtrace: #{e.backtrace}")

  end # def filter

  private
  def validate_query(query, guid = "")

    if query[:status]
      if query[:stdout]['metadata'].nil?
		
	if @cache_invalid_guids && !guid.blank?
	  @app_cache_mutex.synchronize { @app_cache[guid] = {"info" => {}, "expire_at" => Time.now.to_i + @cache_age_time} }
	end
	 
        raise "CF-curl-inavlid: #{query[:stdout]}"
      end
    else
      raise "CF-curl-failed: #{query[:stdout]}"
    end

  end # def validate_query

  private
  def cfcurl(path, body = nil)

    if body.nil?
      cf('curl ' + URI::encode(path))
    else
      cf('curl ' + URI::encode(path) + ' -d "' + body.gsub('"', '\"') + '"')
    end

  end # def cfcurl

  private
  def cflogin

    cf( 'login' +
            (@skip_ssl_validation ? ' --skip-ssl-validation' : '') +
            ' -a ' + @cf_api +
            ' -u ' + @cf_user +
            ' -p ' + @cf_password +
            ' -o ' + @cf_org +
            ' -s ' + @cf_space )

  end # def cflogin

  private
  def cf(cmd)
    stdout, stderr, status = Open3.capture3({"CF_HOME" => "#{@cf_home}"}, "cf #{cmd}")	
    command_output = { :stdout => valid_json?(stdout), :stderr => stderr, :status => status.success?}
    command_output
  end # def cf

  private
  def valid_json?(stdout)

    begin
      JSON.parse(stdout)
    rescue Exception => e
      stdout
    end

  end # def valid_json?

end # class Logstash::Filters::CloudFoundry
