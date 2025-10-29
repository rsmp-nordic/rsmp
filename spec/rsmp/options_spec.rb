require 'rsmp'
require 'tempfile'

RSpec.describe RSMP::Options do
  describe RSMP::Site::Options do
    it 'applies defaults and preserves overrides for components main' do
      options = described_class.new(
        'components' => {
          'main' => { 'TC' => {} }
        }
      )

      expect(options.to_h['site_id']).to eq('RN+SI0001')
      expect(options.to_h['components']['main'].keys).to contain_exactly('TC')
    end

    it 'validates schema types' do
      expect { described_class.new('supervisors' => 'invalid') }
        .to raise_error(RSMP::ConfigurationError, /supervisors/)
    end

    it 'loads from file and extracts log settings' do
      file = Tempfile.new(['rsmp-site', '.yaml'])
      file.write({
        'site_id' => 'RN+SI1234',
        'log' => { 'json' => true }
      }.to_yaml)
      file.close

      options = described_class.load_file(file.path)

      expect(options.to_h['site_id']).to eq('RN+SI1234')
      expect(options.log_settings['json']).to be(true)
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

      expect { described_class.load_file(file.path) }
        .to raise_error(RSMP::ConfigurationError, /supervisors/)
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

      expect { described_class.load_file(file.path) }
        .to raise_error(RSMP::ConfigurationError) { |error|
          expect(error.message).to match(%r{/supervisors})
          expect(error.message).to include('schema')
        }
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

      expect { described_class.load_file(file.path) }
        .to raise_error(RSMP::ConfigurationError) { |error|
          expect(error.message).to include('value at `/supervisors` is not an array')
          expect(error.message).to include('value at `/site_id` is not a string')
        }
    ensure
      file.close
      file.unlink
    end
  end

  describe RSMP::Supervisor::Options do
    it 'applies defaults for guest settings' do
      options = described_class.new({})

      expect(options.to_h['port']).to eq(12_111)
      expect(options.to_h['guest']['sxl']).to eq('tlc')
    end

    it 'rejects invalid config files on load' do
      file = Tempfile.new(['rsmp-supervisor-invalid', '.yaml'])
      file.write({
        'guest' => 'invalid'
      }.to_yaml)
      file.close

      expect { described_class.load_file(file.path) }
        .to raise_error(RSMP::ConfigurationError, /guest/)
    ensure
      file.close
      file.unlink
    end

    it 'supports dig with default and assume values' do
      options = described_class.new({})

      expect(options.dig('missing', default: 'fallback')).to eq('fallback')
      expect(options.dig('missing', assume: 'assumed')).to eq('assumed')
      expect { options.dig('missing', 'nested') }
        .to raise_error(RSMP::ConfigurationError, /missing/)
    end
  end
end
