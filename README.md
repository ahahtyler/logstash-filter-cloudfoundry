# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

The Cloud Foundry filter will add the following meta-data to an application logs
- Org name
- Space name
- Application name

Cloud Foundry only provides the applications GUID and logtype when shipping logs directly from the loggregator. This filter will use that guid and the Cloud Foundry CLI to look up information about your application. 

That being said, for this filter to work you will need the CF CLI installed on your system. (https://github.com/cloudfoundry/cli).

This filter can be used by any user in the Cloud Foundry environemnt that has the "space developer" role for the applications you want to collect data from (not only administrators). However, being an administrator does allow you to set up a more felxibile logging architecture, this fliter was designed to help app teams migrating to the cloud easily hook into thier existing ELK stacks. 

This filter only processes 1 event at a time so the use of this filter can significantly slow down your pipeline's throughput if you have a high latency network. A cache containt GUID and application data is put in place to minimize the number of connections the filter will need to make. Instead of preforming a look up on every single Cloud Foundry log, the filter will look up the log the first time and refer to the cache for subsiquent calls (until the item is removed from the cache). The cache parameters should be configured according to your network and pipelines preformance. 

Here are some example configurations:

   filter{
     cloudfoundry{
         cf_api      => "https://api.cf-domain.com"
         cf_user     => username
         cf_password => password
         cf_org      => "system"
         cf_space    => "apps_manager"
     }
   }

-------------------------------------------------------

   filter{
     if "zone1" in [tags]
         cloudfoundry{
             cf_api      => "https://api.cf-domain1.com"
             ....
         }
     }
     if "zone2" in [tags]
         cloudfoundry{
             cf_api      => "https://api.cf-domain2.com"
             ....
         }
     }
   }


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
