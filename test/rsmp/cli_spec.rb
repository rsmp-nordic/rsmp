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

  it 'displays help' do
    result = invoke_cli('help')

    expect(result.status).to be == 0
    expect(result.output).to be(:include?, 'Commands:')
    expect(result.output).to be(:include?, 'site')
    expect(result.output).to be(:include?, 'supervisor')
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
  end

  with 'supervisor command' do
    it 'reports invalid config files' do
      with_temp_config('supervisor_invalid.yaml', "default: invalid\n") do |path|
        result = invoke_cli('supervisor', '-c', path)

        expect(result.output).to be(:include?, 'Invalid configuration')
        expect(result.output).to be(:include?, '/default')
        expect(result.output).to be(:include?, 'expected object, got string')
      end
    end
  end
end
