Gem::Specification.new do |s|
  s.name          = 'logstash-filter-cloudfoundry'
  s.version       = '0.1.0'
  s.licenses      = ['Apache License (2.0)']
  s.summary       = "Plugin used to assign meta-data to cloud foundry logs"
  s.description   = "This gem is a logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/plugin install gemname. This gem is not a stand-alone program"
  s.authors       = ["Tyler Stigliano"]
  s.email         = 'info@elastic.co'
  s.homepage      = "https://github.com/logstash-plugins/logstash-filter-example/"
  s.require_paths = ["lib"]

  # Files
  s.files = `git ls-files`.split($\)
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "filter" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core", '>= 1.4.0', '< 3.0.0'
  #s.add_runtime_dependency "json"  
  #s.add_runtime_dependency "open-uri"
  #s.add_runtime_dependency "rufus/scheduler"
  #s.add_runtime_dependency "open3"
  
  s.add_development_dependency 'logstash-devutils'
end
