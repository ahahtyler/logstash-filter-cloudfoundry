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
          "cf_org"      => "",
          "cf_space"    => ""}
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
          "cf_org"      => "bad data",
          "cf_space"    => "bad data"}
      end

      it "failed variables are set" do
        expect(plugin.instance_variable_get(:@cf_logged_in)).to eq(false)
        expect(plugin.instance_variable_get(:@cf_retry_cli)).to eq(false)
      end

      it "CF HOME variable was set" do
        expect(File.directory?(plugin.instance_variable_get(:@cf_path))).to be(true)
      end
    end

    describe "got valid data without retry" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "development"}
      end

      it "successful variables are set" do
        expect(plugin.instance_variable_get(:@cf_logged_in)).to eq(true)
        expect(plugin.instance_variable_get(:@cf_retry_cli)).to eq(false)
      end

      it "CF HOME variable was set" do
        expect(File.directory?(plugin.instance_variable_get(:@cf_path))).to be(true)
      end
    end

    describe "got valid data with retry" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "development",
          "cf_retry_cli_timeout" => 10}
      end

      it "successful variables are set" do
        expect(plugin.instance_variable_get(:@cf_logged_in)).to eq(true)
        expect(plugin.instance_variable_get(:@cf_retry_cli)).to eq(true)
      end

      it "CF HOME variable was set" do
        expect(File.directory?(plugin.instance_variable_get(:@cf_path))).to be(true)
      end
    end

  end

  describe "filtering" do

    before(:each) do
      plugin.register
    end

    describe "got valid data" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "development"}
      end

      let(:doc) { "abc loggregator 964db4e9-4f9c-42a2-9296-f8381ce459eb sample log" }

      it "extract all the values" do
        plugin.filter(event)
        expect(event.get("orgname")).to eq("ITCS")
        expect(event.get("spacename")).to eq("development")
        expect(event.get("appname")).to eq("spring-music")
        expect(event.get("appguid")).to eq("964db4e9-4f9c-42a2-9296-f8381ce459eb")
      end

      it "extract all values from cache" do
        plugin.filter(event)
        expect(plugin.instance_variable_get(:@app_cache)[event.get("appguid")].nil?).to be(false)
      end
    end

    describe "got valid data from different space" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "test"}
      end

      let(:doc) { "abc loggregator 964db4e9-4f9c-42a2-9296-f8381ce459eb sample log" }

      it "extract all the values" do
        plugin.filter(event)
        expect(event.get("orgname")).to eq("ITCS")
        expect(event.get("spacename")).to eq("development")
        expect(event.get("appname")).to eq("spring-music")
        expect(event.get("appguid")).to eq("964db4e9-4f9c-42a2-9296-f8381ce459eb")
      end

      it "extract all values from cache" do
        plugin.filter(event)
        expect(plugin.instance_variable_get(:@app_cache)[event.get("appguid")].nil?).to be(false)
      end
    end

    describe "got valid data with invalid guid" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "test",
          "cache_invalid_guids" => false}
      end

      let(:doc) { "abc loggregator aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee sample log" }

      it "make sure cache is empty" do
        plugin.filter(event)
        expect(plugin.instance_variable_get(:@app_cache)[event.get("appguid")].nil?).to be(true)
      end

    end

    describe "got valid data with invalid guid" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "test",
          "cache_invalid_guids" => true}
      end

      let(:doc) { "abc loggregator aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee sample log" }

      it "make sure cache has value" do
        plugin.filter(event)
        expect(plugin.instance_variable_get(:@app_cache)[event.get("appguid")].nil?).to be(false)
      end
    end

    describe "got valid data with no guid" do
      let(:config) do {
          "cf_api"      => "https://api.run.pivotal.io",
          "cf_user"     => "username",
          "cf_password" => "password",
          "cf_org"      => "ITCS",
          "cf_space"    => "test"}
      end

      let(:doc) { "sample log" }

      it "make sure flags are set" do
        plugin.filter(event)
        expect(event.get("appguid").nil?).to eq(true)
      end
    end

  end

end
