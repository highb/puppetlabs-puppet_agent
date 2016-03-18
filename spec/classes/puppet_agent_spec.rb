require 'spec_helper'

describe 'puppet_agent' do
  package_version = '1.2.5'
  global_params = {
    :package_version => package_version
  }

  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          if os =~ /sles/
            facts.merge({
              :is_pe => true,
              :operatingsystemmajrelease => facts[:operatingsystemrelease].split('.')[0],
            })
          else
            facts
          end
        end

        before(:each) do
          if os =~ /sles/
            # Need to mock the PE functions

            Puppet::Parser::Functions.newfunction(:pe_build_version, :type => :rvalue) do |args|
              '4.0.0'
            end

            Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, :type => :rvalue) do |args|
              '1.2.5'
            end
          end
        end

        if Puppet.version < "3.8.0"
          it { expect { is_expected.to contain_package('puppet_agent') }.to raise_error(Puppet::Error, /upgrading requires at least Puppet 3.8/) }
        else
          [{}, {:service_names => []}].each do |params|
            context "puppet_agent class without any parameters" do
              let(:params) { params.merge(global_params) }

              it { is_expected.to compile.with_all_deps }

              it { is_expected.to contain_class('puppet_agent') }
              it { is_expected.to contain_class('puppet_agent::params') }
              it { is_expected.to contain_class('puppet_agent::prepare') }
              it { is_expected.to contain_class('puppet_agent::install').that_requires('puppet_agent::prepare') }

              if facts[:osfamily] == 'RedHat'
                # Workaround PUP-5802/PUP-5025
                yum_package_version = package_version + '-1.el' + facts[:operatingsystemmajrelease]
                it { is_expected.to contain_package('puppet-agent').with_ensure(yum_package_version) }
              else
                it { is_expected.to contain_package('puppet-agent').with_ensure(package_version) }
              end

              if Puppet.version < "4.0.0" && !params[:is_pe]
                it { is_expected.to contain_class('puppet_agent::service').that_requires('puppet_agent::install') }
              end

              if params[:service_names].nil?
                if Puppet.version < "4.0.0" && !params[:is_pe]
                  it { is_expected.to contain_service('puppet') }
                  it { is_expected.to contain_service('mcollective') }
                end
              else
                it { is_expected.to_not contain_service('puppet') }
                it { is_expected.to_not contain_service('mcollective') }
              end
            end
          end
        end
      end
    end
  end

  context 'unsupported operating system', :unless => Puppet.version < "3.8.0" do
    describe 'puppet_agent class without any parameters on Solaris/Nexenta' do
      let(:facts) {{
        :osfamily        => 'Solaris',
        :operatingsystem => 'Nexenta',
        :puppet_ssldir   => '/dev/null/ssl',
        :puppet_config   => '/dev/null/puppet.conf',
        :architecture    => 'i386',
      }}
      let(:params) { global_params }

      it { is_expected.to raise_error(Puppet::Error, /Nexenta not supported/) }
    end
  end
end
