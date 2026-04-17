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
      expect(options.to_h['default']['sxl']).to be == 'tlc'
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

    it 'supports dig with default and assume values' do
      options = RSMP::Supervisor::Options.new({})

      expect(options.dig('missing', default: 'fallback')).to be == 'fallback'
      expect(options.dig('missing', assume: 'assumed')).to be == 'assumed'
      expect { options.dig('missing', 'nested') }
        .to raise_exception(RSMP::ConfigurationError, message: be =~ /missing/)
    end
  end
end
