# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/cloudfoundry"

describe LogStash::Filters::CloudFoundry do

  subject(:plugin) { LogStash::Filters::CloudFoundry.new(config) }
  let(:config) { Hash.new }

  let(:doc)   { "" }
  let(:event) { LogStash::Event.new("message" => doc) }

  describe "Receive" do

    before(:each) do
      plugin.register
    end

    describe "Curl CF CLI" do

      let(:config) { {"cf_api"      => "https://api.run.pivotal.io",
                      "cf_user"     => "username",
                      "cf_password" => "password",
                      "cf_org"      => "ITCS",
                      "cf_space"    => "development"} }

      let(:doc) { "abc loggregator 964db4e9-4f9c-42a2-9296-f8381ce459eb sample log" }

      it "extract all the values" do
        plugin.filter(event)
        expect(event.get("orgname")).to eq("ITCS")
        expect(event.get("spacename")).to eq("development")
	expect(event.get("appname")).to eq("spring-music")
	expect(event.get("appguid")).to eq("964db4e9-4f9c-42a2-9296-f8381ce459eb")
      end

    end

  end

end
