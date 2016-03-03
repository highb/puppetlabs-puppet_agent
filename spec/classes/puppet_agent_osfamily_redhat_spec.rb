require 'spec_helper'

describe 'puppet_agent', :unless => Puppet.version < "3.8.0" do
  [['Fedora', 'fedora/f$releasever'], ['CentOS', 'el/$releasever'], ['Amazon', 'el/6']].each do |os, urlbit|
    context "with #{os} and #{urlbit}" do
      let(:facts) {{
        :osfamily => 'RedHat',
        :operatingsystem => os,
        :architecture => 'x64',
        :servername   => 'master.example.vm',
        :clientcert   => 'foo.example.vm',
      }}

      it { is_expected.to contain_exec('import-RPM-GPG-KEY-puppetlabs').with({
        'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
        'command'   => 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs',
        'unless'    => 'rpm -q gpg-pubkey-`echo $(gpg --throw-keyids < /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs) | cut --characters=11-18 | tr [A-Z] [a-z]`',
        'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs]',
        'logoutput' => 'on_failure',
      }) }

      ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
        it { is_expected.to contain_file(path).with({
          'ensure' => 'directory',
        }) }
      end

      it { is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs').with({
        'ensure' => 'present',
        'owner'  => '0',
        'group'  => '0',
        'mode'   => '0644',
        'source' => 'puppet:///modules/puppet_agent/RPM-GPG-KEY-puppetlabs',
      }) }

      context 'when FOSS' do
        it { is_expected.not_to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }
        it { is_expected.to contain_yumrepo('pc_repo').with({
          'baseurl' => "https://yum.puppetlabs.com/#{urlbit}/PC1/x64",
          'enabled' => 'true',
            'gpgcheck' => '1',
            'gpgkey' => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs',
        }) }

        it { is_expected.to contain_class("puppet_agent::osfamily::redhat") }
      end
    end
  end

  [['RedHat', 'el-7-x86_64', 'el-7-x86_64'], ['Amazon', '', 'el-6-x64']].each do |os, tag, repodir|
    context "when PE on #{os}" do
      before(:each) do
        # Need to mock the PE functions

        Puppet::Parser::Functions.newfunction(:pe_build_version, :type => :rvalue) do |args|
          '4.0.0'
        end

        Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, :type => :rvalue) do |args|
          '1.2.5'
        end
      end

      let(:facts) {{
        :osfamily => 'RedHat',
        :operatingsystem => os,
        :architecture => 'x64',
        :servername   => 'master.example.vm',
        :clientcert   => 'foo.example.vm',
        :is_pe        => true,
        :platform_tag => tag,
      }}

      it { is_expected.to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }

      it { is_expected.to contain_yumrepo('pc_repo').with({
        'baseurl' => "https://master.example.vm:8140/packages/4.0.0/#{repodir}",
        'enabled' => 'true',
        'gpgcheck' => '1',
        'gpgkey' => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs',
        'sslcacert' => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
        'sslclientcert' => '/etc/puppetlabs/puppet/ssl/certs/foo.example.vm.pem',
        'sslclientkey' => '/etc/puppetlabs/puppet/ssl/private_keys/foo.example.vm.pem',
      }) }

      it { is_expected.to contain_class("puppet_agent::osfamily::redhat") }
    end
  end
end
