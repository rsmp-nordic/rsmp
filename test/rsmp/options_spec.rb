require 'rsmp'
require 'tempfile'

describe RSMP::Options do
  with RSMP::Site::Options do
    it 'applies defaults and preserves overrides for components main' do
      options = RSMP::Site::Options.new(
        'components' => {
          'main' => { 'TC' => {} }
        }
      )

      expect(options.to_h['site_id']).to be == 'RN+SI0001'
      expect(options.to_h['components']['main'].keys).to be == ['TC']
    end

    it 'validates schema types' do
      expect { RSMP::Site::Options.new('supervisors' => 'invalid') }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ /supervisors/)
    end

    it 'applies message buffer defaults' do
      options = RSMP::Site::Options.new({})

      expect(options.to_h['message_buffer']).to be == {
        'max_messages' => 10_000,
        'statuses' => true
      }
    end

    it 'validates message buffer status selectors' do
      expect do
        RSMP::Site::Options.new(
          'message_buffer' => {
            'statuses' => [{ 'n' => 'status' }]
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ /message_buffer/)
    end

    it 'rejects unknown nested config keys' do
      expect do
        RSMP::TLC::TrafficControllerSite::Options.new(
          'intervals' => { 'watchdogs' => 1 }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/intervals/watchdogs})
    end

    it 'rejects unknown component setting keys' do
      expect do
        RSMP::TLC::TrafficControllerSite::Options.new(
          'components' => {
            'main' => {
              'TC' => { 'ntsOid' => 'KK+AG9998=001TC000' }
            }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/components/main/TC/ntsOid})
    end

    it 'rejects invalid nested config types' do
      expect do
        RSMP::TLC::TrafficControllerSite::Options.new(
          'signal_plans' => {
            '1' => { 'cycle_time' => 'fast' }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/signal_plans/1/cycle_time})
    end

    it 'loads from file and extracts log settings' do
      file = Tempfile.new(['rsmp-site', '.yaml'])
      file.write({
        'site_id' => 'RN+SI1234',
        'log' => { 'json' => true }
      }.to_yaml)
      file.close

      options = RSMP::Site::Options.load_file(file.path)

      expect(options.to_h['site_id']).to be == 'RN+SI1234'
      expect(options.log_settings['json']).to be == true
    ensure
      file.close
      file.unlink
    end

    it 'rejects unknown log settings' do
      file = Tempfile.new(['rsmp-site-log-invalid', '.yaml'])
      file.write({
        'site_id' => 'RN+SI1234',
        'log' => { 'jsons' => true }
      }.to_yaml)
      file.close

      expect { RSMP::Site::Options.load_file(file.path) }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/jsons})
    ensure
      file.close
      file.unlink
    end

    it 'rejects invalid log setting types' do
      file = Tempfile.new(['rsmp-site-log-invalid', '.yaml'])
      file.write({
        'site_id' => 'RN+SI1234',
        'log' => { 'debug' => 'yes' }
      }.to_yaml)
      file.close

      expect { RSMP::Site::Options.load_file(file.path) }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/debug})
    ensure
      file.close
      file.unlink
    end

    it 'rejects invalid config files on load' do
      file = Tempfile.new(['rsmp-site-invalid', '.yaml'])
      file.write({
        'supervisors' => 'invalid'
      }.to_yaml)
      file.close

      expect { RSMP::Site::Options.load_file(file.path) }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ /supervisors/)
    ensure
      file.close
      file.unlink
    end

    it 'includes schema details in validation errors' do
      file = Tempfile.new(['rsmp-site-invalid', '.yaml'])
      file.write({
        'supervisors' => 'invalid'
      }.to_yaml)
      file.close

      error = nil
      begin
        RSMP::Site::Options.load_file(file.path)
      rescue RSMP::ConfigurationError => e
        error = e
      end
      expect(error).not.to be_nil
      expect(error.message).to be =~ %r{/supervisors}
      expect(error.message).to be(:include?, 'schema')
    ensure
      file.close
      file.unlink
    end

    it 'includes field-specific error details for supervisors and site_id' do
      file = Tempfile.new(['rsmp-site-invalid', '.yaml'])
      file.write({
        'site_id' => nil,
        'supervisors' => 'invalid'
      }.to_yaml)
      file.close

      error = nil
      begin
        RSMP::Site::Options.load_file(file.path)
      rescue RSMP::ConfigurationError => e
        error = e
      end
      expect(error).not.to be_nil
      expect(error.message).to be(:include?, 'value at `/supervisors` is not an array')
      expect(error.message).to be(:include?, 'value at `/site_id` is not a string')
    ensure
      file.close
      file.unlink
    end
  end

  with RSMP::Supervisor::Options do
    it 'applies defaults settings' do
      options = RSMP::Supervisor::Options.new({})

      expect(options.to_h['port']).to be == 12_111
      expect(options.to_h['default']['sxls']).to be == [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
    end

    it 'normalizes sxls from hash form' do
      options = RSMP::Supervisor::Options.new(
        'default' => {
          'sxls' => {
            'tlc' => '1.3.0',
            'vms' => '1.5.4'
          }
        }
      )

      expect(options.to_h['default']['sxls']).to be == [
        { 'name' => 'tlc', 'version' => '1.3.0' },
        { 'version' => '1.5.4', 'name' => 'vms' }
      ]
    end

    it 'accepts normalized site settings when constructing a TLC site' do
      settings = RSMP::Site::Options.new(
        'sxls' => {
          'tlc' => '1.3.0'
        }
      ).to_h

      site = RSMP::TLC::TrafficControllerSite.new(site_settings: settings)

      expect(site.sxls).to be == [{ 'name' => 'tlc', 'version' => '1.3.0' }]
    end

    it 'accepts normalized supervisor settings when constructing a supervisor' do
      settings = RSMP::Supervisor::Options.new(
        'sites' => {
          'default' => {
            'sxls' => {
              'tlc' => '1.3.0'
            }
          }
        }
      ).to_h

      supervisor = RSMP::Supervisor.new(supervisor_settings: settings)

      expect(supervisor.supervisor_settings.dig('sites', 'default', 'sxls')).to be == [
        { 'name' => 'tlc', 'version' => '1.3.0' }
      ]
    end

    it 'rejects sxls in list form' do
      expect do
        RSMP::Supervisor::Options.new(
          'default' => {
            'sxls' => [{ 'name' => 'tlc', 'version' => '1.3.0' }]
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be == 'sxls must be a hash of SXL names to versions')
    end

    it 'rejects sxls in expanded form' do
      expect do
        RSMP::Supervisor::Options.new(
          'default' => {
            'sxls' => { 'tlc' => { 'version' => '1.3.0' } }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be == 'sxls/tlc must be a version string')
    end

    it 'rejects configured SXL prefix' do
      expect do
        RSMP::Supervisor::Options.new(
          'default' => {
            'sxls' => { 'tlc' => { 'version' => '1.3.0', 'prefix' => 'tlc/' } }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be == 'sxls/tlc must be a version string')
    end

    it 'rejects invalid config files on load' do
      file = Tempfile.new(['rsmp-supervisor-invalid', '.yaml'])
      file.write({
        'default' => 'invalid'
      }.to_yaml)
      file.close

      expect { RSMP::Supervisor::Options.load_file(file.path) }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ /default/)
    ensure
      file.close
      file.unlink
    end

    it 'rejects unknown nested site settings' do
      expect do
        RSMP::Supervisor::Options.new(
          'sites' => {
            'default' => {
              'timeouts' => { 'watchdog_timeout' => 1 }
            }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/sites/default/timeouts/watchdog_timeout})
    end

    it 'uses common component validation for supervisor site settings' do
      expect do
        RSMP::Supervisor::Options.new(
          'sites' => {
            'default' => {
              'components' => {
                'main' => {
                  'TC' => { 'ntsOid' => 'bad' }
                }
              }
            }
          }
        )
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/sites/default/components/main/TC/ntsOid})
    end

    it 'supports dig with default and assume values' do
      options = RSMP::Supervisor::Options.new({})

      expect(options.dig('missing', default: 'fallback')).to be == 'fallback'
      expect(options.dig('missing', assume: 'assumed')).to be == 'assumed'
      expect { options.dig('missing', 'nested') }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ /missing/)
    end
  end
end
