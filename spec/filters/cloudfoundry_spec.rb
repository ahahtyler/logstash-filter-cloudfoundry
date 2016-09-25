require 'logstash/devutils/rspec/spec_helper'
require 'logstash/filters/cloudfoundry'

describe LogStash::Filters::CloudFoundry do

	describe "Retrieving meta-data" do

		config <<-CONFIG
			filter {
				cloudfoundry {
					cf_api      => "https://api.run.pivotal.io"
					cf_user     => "my-username"
					cf_password => "my-password"
					cf_org      => "ITCS"
					cf_space    => "development"
				}
			}
		CONFIG
		
		sample("message" => "abc loggregator 964db4e9-4f9c-42a2-9296-f8381ce459eb sample log") do
			insist { subject.get("appguid") } == "ITCS"
		end

	end #end describe "retrieving meta-data"

end #end LogStash::Filters::CloudFoundry
