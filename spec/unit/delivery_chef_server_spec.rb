require 'spec_helper'
require 'chef/config'
require 'chef/encrypted_data_bag_item'
require 'chef/rest'

describe DeliverySugar::ChefServer do
  let(:example_knife_rb) { File.join(SUPPORT_DIR, 'example_knife.rb') }

  let(:example_config) do
    Chef::Config.from_file(example_knife_rb)
    config = Chef::Config.save
    Chef::Config.reset
    config
  end

  subject { described_class.new(example_knife_rb) }

  describe '#new' do
    context 'when no chef config is passed in during instantiation' do
      let(:deliv_knife_rb) { '/var/opt/delivery/workspace/.chef/knife.rb' }
      it 'defaults to the delivery knife.rb' do
        expect(Chef::Config).to receive(:from_file).with(deliv_knife_rb)
        described_class.new
      end
    end

    context 'when a specific chef config is passed in during instantation' do
      it 'uses that chef config' do
        expect(Chef::Config).to receive(:from_file).with('/my/fake/config.rb')
        described_class.new('/my/fake/config.rb')
      end
    end

    it 'loads a valid chef server configuration' do
      Chef::Config.reset
      before_config = Chef::Config.save
      obj = described_class.new(example_knife_rb)
      after_config = Chef::Config.save

      expect(after_config).to eql(before_config)
      expect(obj.server_config).to eql(example_config)
    end
  end

  describe '#encrypted_data_bag_item' do
    let(:bag_name) { 'delivery-secrets' }
    let(:item_id) { 'ent-org-proj' }
    let(:secret_key_file) { example_config[:encrypted_data_bag_secret] }
    let(:custom_secret_file) { '/path/to/secret/file' }
    let(:secret_file) { double('secret file') }
    let(:results) { double('decrypted hash') }

    it 'returns the decrypted data bag item' do
      expect(Chef::EncryptedDataBagItem).to receive(:load_secret)
        .with(secret_key_file).and_return(secret_file)
      expect(Chef::EncryptedDataBagItem).to receive(:load)
        .with(bag_name, item_id, secret_file).and_return(results)
      expect(subject.encrypted_data_bag_item(bag_name, item_id)).to eql(results)
    end

    it 'allows to pass a custom secret key' do
      expect(Chef::EncryptedDataBagItem).to receive(:load_secret)
        .with(custom_secret_file).and_return(secret_file)
      expect(Chef::EncryptedDataBagItem).to receive(:load)
        .with(bag_name, item_id, secret_file).and_return(results)
      expect(subject.encrypted_data_bag_item(bag_name, item_id, custom_secret_file))
        .to eql(results)
    end
  end

  describe '#cheffish_details' do
    let(:expected_output) do
      {
        chef_server_url: 'https://172.31.6.129/organizations/chef_delivery',
        options: {
          client_name: 'delivery',
          signing_key_filename: File.join(SUPPORT_DIR, 'delivery.pem')
        }
      }
    end

    it 'returns a hash that can be used with Cheffish' do
      expect(subject.cheffish_details).to eql(expected_output)
    end
  end

  describe '#rest' do
    let(:type) { :GET }
    let(:path) { '/pushy/jobs' }
    let(:headers) { double('Headers - Hash') }
    let(:data) { double('API Body - Hash (or false for :get/:delete)') }
    let(:response) { double('API Response - Hash') }
    let(:rest_client) { double('Chef::REST Client', request: response) }

    it 'makes a request against Chef::REST client' do
      expect(Chef::REST).to receive(:new).with(
        example_config[:chef_server_url],
        example_config[:node_name],
        example_config[:client_key]
      ).and_return(rest_client)
      expect(rest_client).to receive(:request).with(type, path, headers, data)
        .and_return(response)
      expect(subject.rest(type, path, headers, data)).to eql(response)
    end
  end

  describe '#with_server_config' do
    it 'runs code block with the chef server\'s Chef::Config' do
      block = lambda do
        subject.with_server_config do
          Chef::Config[:chef_server_url]
        end
      end
      expect(Chef::Config[:chef_server_url])
        .not_to eql(example_config[:chef_server_url])
      expect(block.call).to match(example_config[:chef_server_url])
    end
  end

  describe '#load_server_config' do
    it 'saves current config to the object and loads the server config' do
      Chef::Config.reset
      before_config = Chef::Config.save
      subject.send(:load_server_config)
      after_config = Chef::Config.save

      expect(subject.stored_config).to eql(before_config)
      expect(after_config).to eql(subject.server_config)
    end
  end

  describe '#unload_server_config' do
    before do
      Chef::Config.reset
      subject.send(:load_server_config)
    end

    it 'restores the saved config from memory' do
      subject.send(:unload_server_config)
      after_config = Chef::Config.save

      expect(subject.server_config).to eql(example_config)
      expect(after_config).to eql(subject.stored_config)
    end
  end
end