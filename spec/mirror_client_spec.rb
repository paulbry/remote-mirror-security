# frozen_string_literal: true

###############################################################################
# Copyright (c) 2020, Lawrence Livermore National Security, LLC
# Produced at the Lawrence Livermore National Laboratory
# Written by Thomas Mendoza mendoza33@llnl.gov
# LLNL-CODE-801838
# All rights reserved
#
# This file is part of Remote Mirror Security:
# https://github.com/LLNL/remote-mirror-security
#
# SPDX-License-Identifier: MIT
###############################################################################

require 'json'
require 'ostruct'
require 'fileutils'
require 'mirror_client'

# serializable mock object
class MockObject
  def as_json(*)
    { klass: self.class.name, test: 'foo' }
  end

  def to_json(*options)
    as_json(*options).to_json(*options)
  end

  def self.from_json(json_obj)
    new(json_obj[:test])
  end

  def initialize(*); end
end

RSpec.describe CachingMirrorClient, '#unit' do
  before(:each) do
    @client = {}
    @cache_dir = '/tmp/test'
    FileUtils.rm_rf @cache_dir if File.exist? @cache_dir
    @mirror_client = CachingMirrorClient.new(@client, cache_dir: @cache_dir)
  end

  context 'methods to support caching' do
    it 'produces a unique key for the cache' do
      # TODO edges
      method_name = 'foo'
      args = [1, 2, { bar: 3 }]
      args_different = [1, 2]
      first_key = @mirror_client.cache_key(method_name, args)
      expect(first_key.length).not_to be 0
      second_key = @mirror_client.cache_key(method_name, args_different)
      expect(second_key).not_to eq first_key
    end

  end

  context 'accepts an "expires" keyword argument but does not pass it on' do
    it 'strips the expires keyword arg from the args list and returns it' do
      args = [1, 2, { bar: 3, expires: 300 }]
      expect(args[-1].length).to eq 2
      expires = @mirror_client.strip_expires(args)
      expect(expires.is_a?(Time)).to be true
      expect(args.length).to eq 3
      expect(args[-1].length).to eq 1
    end

    it 'uses a default expiration if no expiration is provided' do
      args = [1, 2, { bar: 3 }]
      expires = @mirror_client.strip_expires(args)
      expect(expires.is_a?(Time)).to be true
      expect(expires >= Time.now).to be true
      no_kwargs = [1, 2]
      expires = @mirror_client.strip_expires(no_kwargs)
      expect(expires.is_a?(Time)).to be true
      expect(expires >= Time.now).to be true
    end
  end

  context 'restores previously serialized objects' do
    it 'can restore a hash of objects from json' do
      data = JSON.parse(
        JSON.dump((1..1000).map { |i| [i, MockObject.new] }.to_h),
        symbolize_names: true
      )
      restored = @mirror_client.restore_objects(data)
      expect(restored.values.first.is_a?(MockObject)).to be true
    end

    it 'can restore a single object from json' do
      data = JSON.parse(
        JSON.dump(MockObject.new),
        symbolize_names: true
      )
      restored = @mirror_client.restore_objects(data)
      expect(restored.is_a?(MockObject)).to be true
    end

    it 'can restore an array of objects from json' do
      data = JSON.parse(
        JSON.dump((1..1000).map { MockObject.new }),
        symbolize_names: true
      )
      restored = @mirror_client.restore_objects(data)
      expect(restored.first.is_a?(MockObject)).to be true
    end
  end

  context 'builds a cache of objects' do
    it 'writes data to a file and stores it in memory' do
      key = 'foo'
      data = { bar: 'baz' }
      @mirror_client.write_cache(key, data)
      expect(@mirror_client.cache[key]).to be data
      expect(File.exist?(@mirror_client.cache_file(key))).to be true
    end

    it 'returns data stored in memory' do
      #TODO the rest of read
      key = 'foo'
      data = { bar: 'baz', expires: Time.now + 300 }
      @mirror_client.write_cache(key, data)
      cached = @mirror_client.read_cache(key)
      expect(cached).to be data
    end
  end
end
