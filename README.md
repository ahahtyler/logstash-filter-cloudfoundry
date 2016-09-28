# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

The Cloud Foundry filter will add the following meta-data to an application log
- Org name
- Space name
- Application name

Cloud Foundry only provides an applications GUID when shipping logs directly from the loggregator when using a syslog drain. This filter will use that GUID and the Cloud Foundry CLI to look up information about your application. 

That being said, for this filter to work you will need the CF CLI installed on your system. (https://github.com/cloudfoundry/cli).

This filter only processes 1 event at a time so the use of this filter can significantly slow down your pipeline's throughput if you have a high latency network. When the filter is initialized a cache will be created that will containt an applications GUID and relevant data. This is put in place to minimize the number of connections the filter will need to make. Instead of preforming a look up on every single Cloud Foundry log, the filter will look up the log the first time and refer to the cache for subsiquent calls (until the item is removed from the cache). The cache parameters should be configured according to your network and pipelines preformance. 

In the event of a network or Cloud Foundry outage, the filter has some safeguards to protect your pipelines throughput. If the Cloud Foundry endpoint becomes unreachable you can set a timeout period before the CF CLI tries to communicate with the Cloud Foundry endpoint again. 

This filter can be used by any user in the Cloud Foundry environemnt that has the "space developer" role for the applications you want to collect data from. Additionall, this filter supports paralle CF CLI logins. Meaning, if you have multiple Cloud Foundry endpoints, this filter can gracefully handle collecting data from both of them at the time. 

Below is a list of the available config fields
- cf_api : The Cloud Foundry API endpoint
- cf_user: A valid Cloud Foundry user that has premission to the applications you want data for
- cf_password: The users password
- cf_org: A valid Cloud Foundry org that a user has premission to (required for a successful login)
- cf_space: A valid Cloud Foundry space in the selected org that a user has premission to (required for a successful login)
- skip_ssl_validation: A boolean flag to skip ssl validation on login
- cache_flush_time: How often you want the job to clean out the cache to run
- cace_age_time: A cache items time to live
- cf_retry_cli_timeout: After a failed attempt to reach the Cloud Foundry endpoint, how long should the filter wait before using the cf   CLI again
- cache_invalid_guids: If the Cloud Foundry API receives an invalid guid, cache it so the plugin won't waste resources continuously      trying to look it up
 
Here are some example configurations:
```sh
filter{
  cloudfoundry{
    cf_api      => "https://api.cf-domain.com"
    cf_user     => "username"
    cf_password => "password"
    cf_org      => "system"
    cf_space    => "apps_manager"
    skip_ssl_validation => true
    cache_flush_time => "10m"
    cache_age_time => 600
    cache_invalid_guids => false
  }
}
```
## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-filter-awesome", :path => "/your/local/logstash-filter-awesome"
```
- Install plugin
```sh
bin/plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e 'filter {awesome {}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-awesome.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/plugin install /your/local/plugin/logstash-filter-awesome.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elasticsearch/logstash/blob/master/CONTRIBUTING.md) file.
