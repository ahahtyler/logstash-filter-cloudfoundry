# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/cloudfoundry"

describe LogStash::Filters::CloudFoundry do

  subject(:plugin) { LogStash::Filters::CloudFoundry.new(config) }
  let(:config) { Hash.new }

  let(:doc)   { "" }
  let(:event) { LogStash::Event.new("message" => doc) }

  #Received invalid config inputs
  describe "registration" do

    before(:each) do
    #  plugin.register
    end
  
    context "got blank required data" do
      let(:config) do
        {
			 "cf_api"      => "abc",
			 "cf_user"     => "asd",
			 "cf_password" => "water1",
			 "cf_org"      => "ITCS",
			 "cf_space"    => "development"}
      end

      let(:doc) { "sample log" }

      it "should register" do
        #expect(plugin.cf_api.empty?).to be(false)
        #expect(plugin.cf_user.empty?).to be(false)
        #expect(plugin.cf_password.empty?).to be(false)
        #expect(plugin.cf_org.empty?).to be(false)
        #expect(plugin.cf_space.empty?).to be(false)
		expect{subject.register}.to raise_error
      end
    end
	
  end
  #Received valid config inputs
  #Check if exception for folder
  #Check if class variables are set @cf_logged_in, @login_next, @cf_retry_cli


end
