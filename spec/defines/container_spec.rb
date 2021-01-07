require 'spec_helper'

describe 'podman::container' do
  let(:title) { 'my_container' }
  let(:params) { {
    user: 'my_user',
    image: 'quay.io/fatherlinux/ubi-micro:latest',
    uid: 1000,
    gid: 1000,
  } }
  let(:pre_condition) { 'Exec{path => "/bin"}' }
  on_supported_os.each do |os, os_facts|
    let(:facts) { os_facts }
    context "on #{os}" do
      it { is_expected.to compile }
    end

    context "as userpod" do
      let(:params) { super().merge(
        deployment_mode: 'userpod',
        pod_file: "some\npod",
      ).tap { |hs| hs.delete(:image) } }
      it { is_expected.to compile }
    end
    context "as pod" do
      let(:params) { super().merge(
        deployment_mode: 'pod',
        pod_file: "some\npod",
      ).tap { |hs| hs.delete(:image) } }
      it { is_expected.to compile }
    end
  end
end
