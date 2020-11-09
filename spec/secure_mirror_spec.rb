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

require 'spec_helper'

RSpec.describe SecureMirror, '#unit' do
  include FakeFS::SpecHelpers

  after(:each) do
    f = SecureMirror.mirrored_status_file
    File.unlink f if File.exist? f
  end

  describe '.evaluate_changes' do
    let(:config_filename) { __dir__ + '/secure_mirror/fixtures/config.json' }
    let(:git_config_file) { __dir__ + '/secure_mirror/fixtures/github-config' }

    before do
      FakeFS::FileSystem.clone(config_filename)
      FakeFS::FileSystem.clone(git_config_file)
    end

    context 'update phase' do
      it 'returns a success code' do
        expect(SecureMirror
          .evaluate_changes('update', 'gitlab', config_file: config_filename, git_config_file: git_config_file)
        ).to eq (SecureMirror::Codes::OK)
      end
    end

    context 'pre-receive phase' do
      let(:member_names) { ['apple', 'orange', 'banana'] }
      let(:two_factor_member_names) { ['orange', 'banana'] }
      let(:two_factor_members) do
        two_factor_member_names.map { |name| { login: name } }
      end
      let(:members) do
        member_names.map { |name| { login: name } }
      end
      let(:github_headers) do
        {
          'Accept'=>'application/vnd.github.v3+json',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Authorization'=>'token',
          'Content-Type'=>'application/json',
          'User-Agent'=>'Octokit Ruby Gem 4.19.0'
        }
      end
      let(:gitlab_headers) do
        {
          'Accept'=>'*/*',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'User-Agent'=>'Ruby'
        }
      end

      before do
        allow(ENV).to receive(:[]).with('SM_LOG_LEVEL').and_call_original
        allow(ENV).to receive(:[]).with('HTTP_PROXY').and_call_original
        allow(ENV).to receive(:[]).with('http_proxy').and_call_original
        allow(ENV).to receive(:[]).with('GL_REPOSITORY').and_return('project-test')
        allow(SecureMirror).to receive(:gitlab_shell_config).and_return({'gitlab_url' => 'http://test.gitlab.com'})

        stub_request(:get, "http://test.gitlab.com/api/v4/projects/test").
          with(headers: gitlab_headers).
          to_return { |request| { body: {'mirror' => true }.to_json } }

        stub_request(:get, "https://api.github.com/repos/LLNL/Umpire/collaborators?per_page=100").
          with(headers: github_headers).
          to_return(status: 200, body: members, headers: {})

        stub_request(:get, "https://api.github.com/orgs/Foo/members?filter=2fa_disabled&per_page=100").
          with(headers: github_headers).
          to_return(status: 200, body: two_factor_members, headers: {})

         stub_request(:get, "https://api.github.com/orgs/Foo/members?per_page=100").
          with(headers: github_headers).
          to_return(status: 200, body: members, headers: {})
      end

      it 'returns a success code' do
        expect(SecureMirror
          .evaluate_changes('pre-receive', 'gitlab', config_file: config_filename, git_config_file: git_config_file)
        ).to eq (SecureMirror::Codes::OK)
      end
    end

    context 'post-receive phase' do
      it 'returns a success code' do
        expect(SecureMirror
          .evaluate_changes('post-receive', 'gitlab', config_file: config_filename, git_config_file: git_config_file)
        ).to eq (SecureMirror::Codes::OK)
      end
    end
  end

  context 'helpers' do
    it 'caches mirroring status to a known file' do
      expect(SecureMirror.cache_mirrored_status(true)).to be true
      expect(File.file?(SecureMirror.mirrored_status_file)).to be true
    end

    it 'does not create a file if the mirror status is false' do
      expect(SecureMirror.cache_mirrored_status(false)).to be false
      expect(File.file?(SecureMirror.mirrored_status_file)).to be false
    end

    it 'can remove cached mirror status' do
      SecureMirror.cache_mirrored_status(true)
      expect(SecureMirror.remove_mirrored_status).to be true
      expect(File.file?(SecureMirror.mirrored_status_file)).to be false
    end
  end
end