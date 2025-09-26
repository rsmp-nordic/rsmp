RSpec.describe RSMP::Options do
  describe '.create' do
    it 'creates SiteOptions for :site type' do
      options = RSMP::Options.create(:site)
      expect(options).to be_a(RSMP::Options::SiteOptions)
    end

    it 'creates SupervisorOptions for :supervisor type' do
      options = RSMP::Options.create(:supervisor)
      expect(options).to be_a(RSMP::Options::SupervisorOptions)
    end

    it 'raises error for unknown type' do
      expect {
        RSMP::Options.create(:unknown)
      }.to raise_error(ArgumentError, 'Unknown options type: unknown')
    end
  end
end

RSpec.describe RSMP::Options::BaseOptions do
  let(:test_class) do
    Class.new(RSMP::Options::BaseOptions) do
      def defaults
        {
          'key1' => 'default1',
          'nested' => {
            'key2' => 'default2'
          }
        }
      end
    end
  end

  describe '#initialize' do
    it 'uses defaults when no config provided' do
      options = test_class.new
      expect(options.get('key1')).to eq('default1')
      expect(options.get('nested', 'key2')).to eq('default2')
    end

    it 'merges provided config with defaults' do
      options = test_class.new({'key1' => 'custom1', 'key3' => 'new3'})
      expect(options.get('key1')).to eq('custom1')
      expect(options.get('nested', 'key2')).to eq('default2')
      expect(options.get('key3')).to eq('new3')
    end

    it 'deep merges nested configurations' do
      options = test_class.new({'nested' => {'key3' => 'new3'}})
      expect(options.get('nested', 'key2')).to eq('default2')
      expect(options.get('nested', 'key3')).to eq('new3')
    end
  end

  describe '#get' do
    let(:options) { test_class.new }

    it 'returns value for existing key' do
      expect(options.get('key1')).to eq('default1')
    end

    it 'returns value for nested key' do
      expect(options.get('nested', 'key2')).to eq('default2')
    end

    it 'returns nil for non-existing key' do
      expect(options.get('nonexistent')).to be_nil
    end

    it 'returns nil for non-existing nested key' do
      expect(options.get('nested', 'nonexistent')).to be_nil
    end
  end

  describe '#set' do
    let(:options) { test_class.new }

    it 'sets value for existing key' do
      options.set('key1', 'new_value')
      expect(options.get('key1')).to eq('new_value')
    end

    it 'sets value for nested key' do
      options.set('nested.key2', 'new_nested_value')
      expect(options.get('nested', 'key2')).to eq('new_nested_value')
    end

    it 'creates nested structure for new nested key' do
      options.set('new.nested.key', 'value')
      expect(options.get('new', 'nested', 'key')).to eq('value')
    end
  end

  describe '#to_h' do
    let(:options) { test_class.new({'key1' => 'custom1'}) }

    it 'returns hash representation' do
      result = options.to_h
      expect(result).to be_a(Hash)
      expect(result['key1']).to eq('custom1')
      expect(result['nested']['key2']).to eq('default2')
    end

    it 'returns a copy, not the original' do
      result = options.to_h
      result['key1'] = 'modified'
      expect(options.get('key1')).to eq('custom1')
    end
  end

  describe '#merge!' do
    let(:options) { test_class.new }

    it 'merges additional configuration' do
      options.merge!({'key1' => 'merged1', 'key3' => 'new3'})
      expect(options.get('key1')).to eq('merged1')
      expect(options.get('key3')).to eq('new3')
      expect(options.get('nested', 'key2')).to eq('default2')
    end

    it 'returns self' do
      result = options.merge!({'key1' => 'merged1'})
      expect(result).to eq(options)
    end
  end

  describe '#valid?' do
    it 'returns true for valid configuration' do
      options = test_class.new
      expect(options).to be_valid
    end
  end
end

RSpec.describe RSMP::Options::SiteOptions do
  describe '#initialize' do
    it 'uses defaults when no config provided' do
      options = RSMP::Options::SiteOptions.new
      expect(options.site_id).to eq('RN+SI0001')
      expect(options.sxl).to eq('tlc')
      expect(options.supervisors).to eq([{ 'ip' => '127.0.0.1', 'port' => 12111 }])
    end

    it 'accepts custom configuration' do
      config = {
        'site_id' => 'CUSTOM+ID',
        'sxl' => 'tlc',  # Use valid SXL type
        'supervisors' => [{ 'ip' => '192.168.1.100', 'port' => 13111 }]
      }
      options = RSMP::Options::SiteOptions.new(config)
      expect(options.site_id).to eq('CUSTOM+ID')
      expect(options.sxl).to eq('tlc')
      expect(options.supervisors).to eq([{ 'ip' => '192.168.1.100', 'port' => 13111 }])
    end

    it 'merges with defaults correctly' do
      config = {
        'site_id' => 'CUSTOM+ID',
        'intervals' => {
          'timer' => 0.5  # Override timer but keep other intervals
        }
      }
      options = RSMP::Options::SiteOptions.new(config)
      expect(options.site_id).to eq('CUSTOM+ID')
      expect(options.intervals['timer']).to eq(0.5)
      expect(options.intervals['watchdog']).to eq(1)  # Default preserved
    end

    it 'loads configuration from YAML file' do
      # Create a temporary YAML file
      require 'tempfile'
      file = Tempfile.new(['test_config', '.yaml'])
      file.write("site_id: TEST+YAML\nsxl: tlc\n")  # Use valid SXL type
      file.close

      options = RSMP::Options::SiteOptions.new(file.path)
      expect(options.site_id).to eq('TEST+YAML')
      expect(options.sxl).to eq('tlc')

      file.unlink
    end

    it 'raises error for non-existent file' do
      expect {
        RSMP::Options::SiteOptions.new('/path/to/nonexistent/file.yaml')
      }.to raise_error(RSMP::ConfigurationError, /Configuration file not found/)
    end
  end

  describe 'accessors' do
    let(:options) { RSMP::Options::SiteOptions.new }

    it 'provides site_id accessor' do
      expect(options.site_id).to eq('RN+SI0001')
      options.site_id = 'NEW+ID'
      expect(options.site_id).to eq('NEW+ID')
    end

    it 'provides supervisors accessor' do
      expect(options.supervisors).to be_an(Array)
      new_supervisors = [{ 'ip' => '10.0.0.1', 'port' => 12111 }]
      options.supervisors = new_supervisors
      expect(options.supervisors).to eq(new_supervisors)
    end

    it 'provides read-only accessors for complex types' do
      expect(options.sxl).to eq('tlc')
      expect(options.sxl_version).to be_a(String)
      expect(options.components).to be_a(Hash)
      expect(options.intervals).to be_a(Hash)
      expect(options.timeouts).to be_a(Hash)
    end

    it 'provides boolean accessor for send_after_connect' do
      expect(options.send_after_connect?).to eq(true)
    end
  end

  describe 'validation' do
    it 'validates required components structure' do
      # We need to create a test that bypasses the default merging for this validation
      # This is more of an edge case test to ensure our validation logic is working
      expect {
        test_class = Class.new(RSMP::Options::SiteOptions) do
          def defaults
            {
              'site_id' => 'TEST',
              'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 12111 }],
              'sxl' => 'tlc',
              'components' => {}  # No main component in defaults
            }
          end
        end
        test_class.new
      }.to raise_error(RSMP::ConfigurationError, /Components must include a 'main' component/)
    end

    it 'accepts valid configuration' do
      config = {
        'site_id' => 'VALID+ID',
        'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 12111 }],
        'sxl' => 'tlc',
        'components' => {
          'main' => { 'C1' => {} }
        }
      }
      expect {
        RSMP::Options::SiteOptions.new(config)
      }.not_to raise_error
    end
  end
end

RSpec.describe RSMP::Options::SupervisorOptions do
  describe '#initialize' do
    it 'uses defaults when no config provided' do
      options = RSMP::Options::SupervisorOptions.new
      expect(options.port).to eq(12111)
      expect(options.ips).to eq('all')
      expect(options.guest_settings).to be_a(Hash)
      expect(options.guest_settings['sxl']).to eq('tlc')
    end

    it 'accepts custom configuration' do
      config = {
        'port' => 13111,
        'ips' => ['192.168.1.1'],
        'guest' => {
          'sxl' => 'tlc'  # Use valid SXL type
        }
      }
      options = RSMP::Options::SupervisorOptions.new(config)
      expect(options.port).to eq(13111)
      expect(options.ips).to eq(['192.168.1.1'])
      expect(options.guest_settings['sxl']).to eq('tlc')
    end
  end

  describe 'accessors' do
    let(:options) { RSMP::Options::SupervisorOptions.new }

    it 'provides port accessor' do
      expect(options.port).to eq(12111)
      options.port = 13111
      expect(options.port).to eq(13111)
    end

    it 'provides read-only accessors' do
      expect(options.ips).to eq('all')
      expect(options.guest_settings).to be_a(Hash)
      expect(options.sites_settings).to be_nil  # Default is nil
    end
  end

  describe 'validation' do
    it 'accepts valid configuration with sites' do
      config = {
        'port' => 12111,
        'guest' => {
          'sxl' => 'tlc'
        },
        'sites' => {
          'SITE1' => {
            'sxl' => 'tlc'
          }
        }
      }
      expect {
        RSMP::Options::SupervisorOptions.new(config)
      }.not_to raise_error
    end

    it 'validates that sites have SXL configured' do
      config = {
        'port' => 12111,
        'guest' => {
          'sxl' => 'tlc'
        },
        'sites' => {
          'SITE1' => {}  # Missing SXL
        }
      }
      expect {
        RSMP::Options::SupervisorOptions.new(config)
      }.to raise_error(RSMP::ConfigurationError, /No SXL specified/)
    end
  end
end