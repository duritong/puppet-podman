require 'spec_helper'

describe 'podman' do
  let(:pre_condition) { 'Exec{path => "/bin"}' }

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      it { is_expected.to contain_package('podman') }
      it { is_expected.to contain_package('slirp4netns') }
      it { is_expected.to contain_package('runc') }

      it { is_expected.to contain_file('/var/lib/containers/users').with(
        :ensure => 'directory',
        :owner  => 'root',
        :group  => 'root',
        :mode   => '0711',
      )}
    end
  end
end
