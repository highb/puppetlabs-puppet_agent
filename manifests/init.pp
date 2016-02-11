# == Class: puppet_agent
#
# Upgrades Puppet 3.8 and newer to the requested version.
# Makes Puppet 4 upgrades easier by migrating SSL certs and config files to the
# new Puppet-Agent paths and removing deprecated settings that are no longer
# supported by Puppet 4.
#
# === Parameters
#
# [arch]
#   The package architecture. Defaults to the architecture fact.
# [collection]
#   The Puppet Collection to track. Defaults to 'PC1'.
# [is_pe]
#   Install from Puppet Enterprise repos. Enabled if communicating with a PE master.
# [package_name]
#   The package to upgrade to, i.e. `puppet-agent`.
# [package_version]
#   The package version to upgrade to. Defaults to undef, meaning only upgrade from Puppet < 4.0.
# [service_names]
#   An array of services to start, normally `puppet` and `mcollective`.
#   None will be started if the array is empty.
# [source]
#   The location to find packages.
#
class puppet_agent (
  $arch            = $::architecture,
  $collection      = 'PC1',
  $is_pe           = $::puppet_agent::params::_is_pe,
  $package_name    = $::puppet_agent::params::package_name,
  $package_version = undef,
  $service_names   = $::puppet_agent::params::service_names,
  $source          = $::puppet_agent::params::_source,
) inherits ::puppet_agent::params {

  validate_re($arch, ['^x86$','^x64$','^i386$','^i86pc$','^amd64$','^x86_64$','^power$','^sun4[uv]$','PowerPC_POWER'])

  if ($package_version == undef and versioncmp("${::clientversion}", '4.0.0') < 0) {
    $_package_version = $puppet_agent::params::master_agent_version
  } elsif ($package_version != undef and versioncmp("${::clientversion}", $package_version) != 0) {
    $_package_version = $package_version
  }

  if versioncmp("${::clientversion}", '3.8.0') < 0 {
    fail('upgrading requires at least Puppet 3.8')
  }
  elsif !$is_pe and versioncmp("${::clientversion}", '4.0.0') >= 0 {
    info('puppet_agent only performs actions on Puppet 4+ when Puppet Enterprise is installed')
  }
  elsif $is_pe and $::aio_agent_version != undef and $_package_version != undef and versioncmp("${::aio_agent_version}", "${_package_version}") >= 0 {
    info("puppet_agent is up to date at package version ${::aio_agent_version}")
  } else {
    if $package_version != undef and $package_version !~ /^\d+\.\d+\.\d+[.-]?\d*$/ {
      fail("invalid version ${package_version} requested")
    }

    if $::architecture == 'x86' and $arch == 'x64' {
      fail('Unable to install x64 on a x86 system')
    }

    if $::operatingsystem == 'SLES' and $::operatingsystemmajrelease == '10' {
      $_package_file_name = "${puppet_agent::package_name}-${_package_version}-1.sles10.${::architecture}.rpm"
    } elsif $::operatingsystem == 'Solaris' and $::operatingsystemmajrelease == '10' {
      if $arch =~ /^sun4[uv]$/ {
        $_package_file_name = "${puppet_agent::package_name}-${_package_version}-1.sparc.pkg.gz"
      } else {
        $_package_file_name = "${puppet_agent::package_name}-${_package_version}-1.i386.pkg.gz"
      }
    } elsif $::operatingsystem == 'Darwin' and $::macosx_productversion_major =~ /10\.[9,10,11]/ {
      $_package_file_name = "${puppet_agent::package_name}-${_package_version}-1.osx${$::macosx_productversion_major}.dmg"
    } elsif $::operatingsystem == 'aix' and $::architecture =~ /PowerPC_POWER[5,6,7]/ {
      $aix_ver_number = regsubst($::platform_tag,'aix-(\d+\.\d+)-power','\1')
      $_package_file_name = "${puppet_agent::package_name}-${puppet_agent::params::master_agent_version}-1.aix${aix_ver_number}.ppc.rpm"
    } elsif $::osfamily == 'windows' {
      $_arch = $::kernelmajversion ?{
        /^5\.\d+/ => 'x86', # x64 is never allowed on windows 2003
        default   => $arch
      }

      if $is_pe {
        $_package_file_name = "${package_name}-${_arch}.msi"
      } else {
        $_package_file_name = "${package_name}-${_arch}-latest.msi"
      }
    } else {
      $_package_file_name = undef
    }

    class { '::puppet_agent::prepare':
      package_file_name => $_package_file_name,
      package_version   => $package_version,
    } ->
    class { '::puppet_agent::install':
      package_file_name => $_package_file_name,
      package_version   => $package_version,
    }

    contain '::puppet_agent::prepare'
    contain '::puppet_agent::install'

    # On windows, our MSI handles the services
    # On PE AIO nodes, PE Agent nodegroup is managing the services
    if $::osfamily != 'windows' and !is_pe and ::aio_agent_version == undef {
      class { '::puppet_agent::service':
        require => Class['::puppet_agent::install'],
      }
      contain '::puppet_agent::service'
    }

  }
}
