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
      plugin.register
    end

    describe "got blank required data" do
      let(:config) do {
            "cf_api"      => "",
            "cf_user"     => "",
            "cf_password" => "",
            "cf_org"      => "ITCS",
            "cf_space"    => "development"}
      end

      it "failed variables are set" do
        expect(plugin.instance_variable_get(:@cf_logged_in)).to eq(false)
        expect(plugin.instance_variable_get(:@cf_retry_cli)).to eq(false)
      end
    end

    describe "got bad data" do
      let(:config) do {
          "cf_api"      => "bad data",
          "cf_user"     => "bad data",
          "cf_password" => "bad data",
          "cf_org"      => "ITCS",
          "cf_space"    => "development"}
      end

      it "failed variables are set" do
        expect(plugin.instance_variable_get(:@cf_logged_in)).to eq(false)
        expect(plugin.instance_variable_get(:@cf_retry_cli)).to eq(false)
        expect(File.directory?(plugin.instance_variable_get(:@cf_path))).to be(false)
      end
    end

  end

end
