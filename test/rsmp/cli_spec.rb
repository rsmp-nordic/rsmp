require 'rsmp/cli'
require 'stringio'
require 'tmpdir'

describe RSMP::CLI do
  CliResult = Struct.new(:status, :output, :error, :site_run, :supervisor_run, keyword_init: true)

  def build_cli_class
    Class.new(RSMP::CLI) do
      class << self
        attr_accessor :site_run, :supervisor_run
      end

      no_commands do
        def run_site(site_class, settings, log_settings)
          self.class.site_run = {
            site_class: site_class,
            settings: settings,
            log_settings: log_settings
          }
        end

        def run_supervisor(settings, log_settings)
          self.class.supervisor_run = {
            settings: settings,
            log_settings: log_settings
          }
        end
      end
    end
  end

  def invoke_cli(*args)
    cli_class = build_cli_class
    stdout = StringIO.new
    stderr = StringIO.new
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = stdout
    $stderr = stderr
    status = 0

    begin
      cli_class.start(args.flatten)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end

    CliResult.new(
      status: status,
      output: stdout.string,
      error: stderr.string,
      site_run: cli_class.site_run,
      supervisor_run: cli_class.supervisor_run
    )
  end

  def with_temp_config(name, content)
    Dir.mktmpdir('rsmp-cli') do |dir|
      path = File.join(dir, name)
      File.write(path, content)
      yield path
    end
  end

  def default_site_port
    RSMP::TLC::TrafficControllerSite::Options.new.to_h.dig('supervisors', 0, 'port')
  end

  it 'displays help' do
    result = invoke_cli('help')

    expect(result.status).to be == 0
    expect(result.output).to be(:include?, 'Commands:')
    expect(result.output).to be(:include?, 'schema')
    expect(result.output).to be(:include?, 'site')
    expect(result.output).to be(:include?, 'supervisor')
    expect(result.output).to be(:include?, 'version')
  end

  it 'displays the version' do
    result = invoke_cli('version')

    expect(result.status).to be == 0
    expect(result.output).to be == "#{RSMP::VERSION}\n"
  end

  with 'site command' do
    it 'uses the TLC site implementation by default' do
      result = invoke_cli('site')

      expect(result.site_run[:site_class]).to be == RSMP::TLC::TrafficControllerSite
      expect(result.site_run[:settings]).to be == {}
      expect(result.site_run[:log_settings]).to be == { 'active' => true }
    end

    it 'shows help' do
      result = invoke_cli('help', 'site')

      expect(result.output).to be(:include?, 'Usage:')
      expect(result.output).to be(:include?, 'Options:')
    end

    it 'applies the site id option' do
      result = invoke_cli('site', '-i', 'RN+SI0639')

      expect(result.site_run[:settings]['site_id']).to be == 'RN+SI0639'
    end

    it 'applies the supervisors option' do
      result = invoke_cli('site', '-s', '127.0.0.8:12118')

      expect(result.site_run[:settings]['supervisors']).to be == [
        { 'ip' => '127.0.0.8', 'port' => '12118' }
      ]
    end

    it 'applies multiple supervisors and default ip values' do
      result = invoke_cli('site', '-s', '127.0.0.8:12118,:12119')

      expect(result.site_run[:settings]['supervisors']).to be == [
        { 'ip' => '127.0.0.8', 'port' => '12118' },
        { 'ip' => '127.0.0.1', 'port' => '12119' }
      ]
    end

    it 'uses the default port for supervisor values without a port' do
      result = invoke_cli('site', '-s', '127.0.0.2')

      expect(result.status).to be == 0
      expect(result.output).to be == ''
      expect(result.site_run[:settings]['supervisors']).to be == [
        { 'ip' => '127.0.0.2', 'port' => default_site_port }
      ]
    end

    it 'uses the configured port for supervisor values without a port' do
      with_temp_config('site.yaml', <<~YAML) do |path|
        supervisors:
          - ip: 127.0.0.1
            port: 13111
      YAML
        result = invoke_cli('site', '-c', path, '-s', '127.0.0.2')

        expect(result.site_run[:settings]['supervisors']).to be == [
          { 'ip' => '127.0.0.2', 'port' => 13_111 }
        ]
      end
    end

    it 'rejects supervisor values with blank ports' do
      result = invoke_cli('site', '-s', '127.0.0.2:')

      expect(result.status).to be == 1
      expect(result.output).to be(:include?, 'Invalid supervisor "127.0.0.2:"')
      expect(result.output).to be(:include?, 'non-empty port')
      expect(result.site_run).to be_nil
    end

    it 'applies core and log options' do
      result = invoke_cli('site', '--core', '3.3.0', '--log', 'traffic.log', '--json')

      expect(result.site_run[:settings]['core_version']).to be == '3.3.0'
      expect(result.site_run[:log_settings]).to be == {
        'active' => true,
        'path' => 'traffic.log',
        'json' => true
      }
    end

    it 'loads config files' do
      with_temp_config('site.yaml', "site_id: RN+SI0932\n") do |path|
        result = invoke_cli('site', '-c', path)

        expect(result.site_run[:settings]['site_id']).to be == 'RN+SI0932'
      end
    end

    it 'reports invalid config files' do
      with_temp_config('site_invalid.yaml', "supervisors: invalid\n") do |path|
        result = invoke_cli('site', '-c', path)

        expect(result.output).to be(:include?, 'Invalid configuration')
        expect(result.output).to be(:include?, '/supervisors')
        expect(result.output).to be(:include?, 'expected array, got string')
      end
    end

    it 'reports missing config files' do
      result = invoke_cli('site', '-c', 'bad/path/site.yaml')

      expect(result.output).to be(:include?, 'Error: Config bad/path/site.yaml not found')
    end

    it 'rejects unknown core versions' do
      result = invoke_cli('site', '--core', '9.9.9')

      expect(result.status).to be == 1
      expect(result.error).to be(:include?, "Expected '--core'")
      expect(result.error).to be(:include?, '9.9.9')
    end

    it 'rejects unknown site types' do
      result = invoke_cli('site', '--type', 'bad')

      expect(result.status).to be == 1
      expect(result.error).to be(:include?, "Expected '--type'")
      expect(result.error).to be(:include?, 'bad')
    end
  end

  with 'supervisor command' do
    it 'uses empty settings by default' do
      result = invoke_cli('supervisor')

      expect(result.supervisor_run[:settings]).to be == {}
      expect(result.supervisor_run[:log_settings]).to be == { 'active' => true }
    end

    it 'shows help' do
      result = invoke_cli('help', 'supervisor')

      expect(result.output).to be(:include?, 'Usage:')
      expect(result.output).to be(:include?, 'Options:')
    end

    it 'applies supervisor options' do
      result = invoke_cli(
        'supervisor',
        '-i', 'RN+SU0639',
        '--ip', '0.0.0.0',
        '-p', '13111',
        '--core', '3.3.0',
        '--log', 'supervisor.log',
        '--json'
      )

      expect(result.supervisor_run[:settings]).to be == {
        'site_id' => 'RN+SU0639',
        'ip' => '0.0.0.0',
        'port' => '13111',
        'default' => { 'core_version' => '3.3.0' }
      }
      expect(result.supervisor_run[:log_settings]).to be == {
        'active' => true,
        'path' => 'supervisor.log',
        'json' => true
      }
    end

    it 'reports invalid config files' do
      with_temp_config('supervisor_invalid.yaml', "default: invalid\n") do |path|
        result = invoke_cli('supervisor', '-c', path)

        expect(result.output).to be(:include?, 'Invalid configuration')
        expect(result.output).to be(:include?, '/default')
        expect(result.output).to be(:include?, 'expected object, got string')
      end
    end

    it 'rejects unknown core versions' do
      result = invoke_cli('supervisor', '--core', '9.9.9')

      expect(result.status).to be == 1
      expect(result.error).to be(:include?, "Expected '--core'")
      expect(result.error).to be(:include?, '9.9.9')
    end
  end

  with 'schema command' do
    it 'reports missing input files' do
      result = invoke_cli('schema', 'generate', '--in', 'missing-sxl.yaml')

      expect(result.status).to be == 1
      expect(result.output).to be(:include?, 'Error: Input file missing-sxl.yaml not found')
    end

    it 'generates an SXL index alongside JSON Schema files' do
      Dir.mktmpdir do |dir|
        input = File.expand_path('../../schemas/tlc/1.3.0/sxl.yaml', __dir__)
        result = invoke_cli('schema', 'generate', '--in', input, '--out', dir)
        index = JSON.parse(File.read(File.join(dir, 'sxl_index.json'), encoding: 'UTF-8'))

        expect(result.status).to be == 0
        expect(index.dig('meta', 'name')).to be == 'tlc'
        expect(index.dig('statuses', 'S0001', 'arguments')).to be(:include?, 'signalgroupstatus')
        expect(index.dig('commands', 'M0001', 'arguments')).to be(:include?, 'status')
        expect(index['alarms']).to be(:include?, 'A0001')
      end
    end

    it 'copies fallback definitions from the minimum core version' do
      with_temp_config('sxl.yaml', minimal_sxl_yaml('minimum_core_version: 3.1.2')) do |input|
        Dir.mktmpdir do |dir|
          result = invoke_cli('schema', 'generate', '--in', input, '--out', dir)
          generated = File.read(File.join(dir, 'defs', 'definitions.json'), encoding: 'UTF-8')
          expected = File.read(File.expand_path('../../schemas/core/3.1.2/definitions.json', __dir__),
                               encoding: 'UTF-8')
          root = JSON.parse(File.read(File.join(dir, 'rsmp.json'), encoding: 'UTF-8'))

          expect(result.status).to be == 0
          expect(generated).to be == expected
          expect(root['minimum_core_version']).to be == '3.1.2'
        end
      end
    end

    it 'uses latest core definitions for legacy SXLs without a minimum core version' do
      with_temp_config('sxl.yaml', minimal_sxl_yaml) do |input|
        Dir.mktmpdir do |dir|
          result = invoke_cli('schema', 'generate', '--in', input, '--out', dir)
          generated = File.read(File.join(dir, 'defs', 'definitions.json'), encoding: 'UTF-8')
          expected = File.read(
            File.expand_path("../../schemas/core/#{RSMP::Schema.latest_core_version}/definitions.json", __dir__),
            encoding: 'UTF-8'
          )

          expect(result.status).to be == 0
          expect(generated).to be == expected
        end
      end
    end

    it 'keeps custom patterns on list values' do
      with_temp_config('sxl.yaml', list_pattern_sxl_yaml) do |input|
        Dir.mktmpdir do |dir|
          result = invoke_cli('schema', 'generate', '--in', input, '--out', dir)
          status = JSON.parse(File.read(File.join(dir, 'statuses', 'S0001.json'), encoding: 'UTF-8'))
          value = status.dig('else', 'allOf', 0, 'then', 'properties', 's')

          expect(result.status).to be == 0
          expect(value['$ref']).to be == '../defs/definitions.json#/string_list'
          expect(value['pattern']).to be == '^(\\d{1,3}\\-\\d{1,3})(?:,(\\d{1,3}\\-\\d{1,3}))*$'
          expect(result.output).to be == ''
        end
      end
    end
  end

  def minimal_sxl_yaml(extra_meta = nil)
    extra_meta = "  #{extra_meta}\n" if extra_meta
    <<~YAML
      ---
      meta:
        name: test
        description: Test SXL
        version: 1.0.0
      #{extra_meta}objects:
        Test Object:
          statuses:
            S0001:
              arguments:
                flag:
                  type: boolean
    YAML
  end

  def list_pattern_sxl_yaml
    <<~YAML
      ---
      meta:
        name: test
        description: Test SXL
        version: 1.0.0
      objects:
        Test Object:
          statuses:
            S0001:
              arguments:
                status:
                  type: string_list_as_string
                  pattern: "^(\\\\d{1,3}\\\\-\\\\d{1,3})(?:,(\\\\d{1,3}\\\\-\\\\d{1,3}))*$"
    YAML
  end
end
