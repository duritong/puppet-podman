require 'spec_helper'

describe 'podman::api_socket' do
  let(:title) { 'my_user' }
  let(:params) do
    {
      uid: 1000,
      gid: 1000,
    }
  end
  let(:pre_condition) { 'Exec{path => "/bin"}' }

  on_supported_os.each do |os, os_facts|
    let(:facts) { os_facts }

    context "on #{os}" do
      it { is_expected.to compile }
    end

  end
end
