require 'thor'
require_relative '../rsmp'
require_relative 'cli/configuration'

module RSMP
  # CLI subcommands for SXL schema operations.
  class SchemaCLI < Thor
    namespace :schema
    desc 'generate', 'Generate JSON Schema files from sxl.yaml'
    method_option :in,  type: :string, aliases: '-i', banner: 'Path to sxl.yaml input file', default: 'sxl.yaml'
    method_option :out, type: :string, aliases: '-o', banner: 'Path to output directory',    default: '.'
    def generate
      input  = options[:in]
      output = options[:out]
      unless File.exist?(input)
        puts "Error: Input file #{input} not found"
        exit 1
      end
      sxl = RSMP::Convert::Import::YAML.read(input)
      RSMP::Convert::Export::JSONSchema.write(sxl, output)
    end
  end

  # CLI subcommands for RSMP configuration validation.
  class ConfigCLI < Thor
    namespace :config
    desc 'check PATH...', 'Validate RSMP site or supervisor config files'
    method_option :type, type: :string, aliases: '-t', default: 'auto',
                         enum: ['auto'] + RSMP::Config.types,
                         banner: 'Config type: auto, site, tlc or supervisor'
    def check(*paths)
      if paths.empty?
        puts 'Error: config check requires at least one path'
        exit 1
      end

      valid = true
      paths.each do |path|
        RSMP::Config.load_file(path, type: options[:type])
        puts 'OK'
      rescue RSMP::ConfigurationError => e
        valid = false
        puts "Error: #{e.message}"
      end

      exit 1 unless valid
    end
  end

  # CLI commands for running RSMP site and supervisor.
  class CLI < Thor
    include Configuration

    desc 'version', 'Show version'
    def version
      puts RSMP::VERSION
    end

    desc 'site', 'Run RSMP site'
    method_option :config, type: :string, aliases: ['-c', '--options'], banner: 'Path to .yaml config file'
    method_option :id, type: :string, aliases: '-i', banner: 'RSMP site id'
    method_option :supervisors, type: :string, aliases: '-s',
                                banner: 'ip:port,... list of supervisor to connect to'
    method_option :core, type: :string, banner: "Core version: [#{RSMP::Schema.core_versions.join(' ')}]", enum: RSMP::Schema.core_versions
    method_option :sxls, type: :string, banner: 'SXL versions as name:version,...'
    method_option :type, type: :string, aliases: '-t', banner: 'Type of site: [tlc]', enum: ['tlc'],
                         default: 'tlc'
    method_option :log, type: :string, aliases: '-l', banner: 'Path to log file'
    method_option :json, type: :boolean, aliases: '-j', banner: 'Show JSON messages in log'
    def site
      settings, log_settings = load_site_configuration
      apply_site_options(settings, log_settings)
      site_class = determine_site_class(settings)
      run_site(site_class, settings, log_settings)
    rescue Interrupt
      # ctrl-c
    rescue RSMP::ConfigurationError => e
      puts "Error: #{e}"
      exit 1
    rescue StandardError => e
      puts "Uncaught error: #{e}"
      puts caller.join("\n")
    end

    desc 'supervisor', 'Run RSMP supervisor'
    method_option :config, type: :string, aliases: ['-c', '--options'], banner: 'Path to .yaml config file'
    method_option :id, type: :string, aliases: '-i', banner: 'RSMP site id'
    method_option :ip, type: :string, banner: 'IP address to listen on'
    method_option :port, type: :string, aliases: '-p', banner: 'Port to listen on'
    method_option :core, type: :string, banner: "Core version: [#{RSMP::Schema.core_versions.join(' ')}]", enum: RSMP::Schema.core_versions
    method_option :sxls, type: :string, banner: 'Default SXL versions as name:version,...'
    method_option :log, type: :string, aliases: '-l', banner: 'Path to log file'
    method_option :json, type: :boolean, aliases: '-j', banner: 'Show JSON messages in log'
    def supervisor
      settings, log_settings = load_supervisor_configuration
      apply_supervisor_options(settings, log_settings)
      run_supervisor(settings, log_settings)
    rescue Interrupt
      # ctrl-c
    end

    register SchemaCLI, 'schema', 'schema COMMAND', 'SXL schema commands'
    register ConfigCLI, 'config', 'config COMMAND', 'Configuration commands'

    private

    def site_options_class
      case site_type
      when 'tlc'
        RSMP::TLC::TrafficControllerSite::Options
      else
        RSMP::Site::Options
      end
    end

    def apply_site_options(settings, log_settings)
      apply_basic_site_options(settings)
      parse_supervisors(settings) if options[:supervisors]
      apply_log_options(log_settings)
    end

    def apply_basic_site_options(settings)
      settings['site_id'] = options[:id] if options[:id]
      settings['core_version'] = options[:core] if options[:core]
      settings['sxls'] = parse_sxls(options[:sxls]) if options[:sxls]
    end

    def parse_sxls(value)
      value.split(',').each_with_object({}) do |item, memo|
        parts = item.split(':')
        unless parts.length == 2
          raise RSMP::ConfigurationError, "Invalid SXLS item #{item.inspect}, expected name:version"
        end

        name, version = parts
        memo[name] = version
      end
    end

    def parse_supervisors(settings)
      default_port = default_supervisor_port(settings)
      settings['supervisors'] = []
      options[:supervisors].split(',').each do |supervisor|
        ip, port = parse_supervisor(supervisor, default_port)
        settings['supervisors'] << { 'ip' => ip, 'port' => port }
      end
    end

    def parse_supervisor(supervisor, default_port)
      parts = supervisor.split(':', -1)

      case parts.size
      when 1
        ip = parts.first
        port = default_port
      when 2
        ip, port = parts
      else
        raise RSMP::ConfigurationError,
              "Invalid supervisor #{supervisor.inspect}, expected ip[:port]"
      end

      if port.nil? || port.to_s.empty?
        raise RSMP::ConfigurationError,
              "Invalid supervisor #{supervisor.inspect}, expected ip[:port] with a non-empty port"
      end

      ip = '127.0.0.1' if ip.empty?
      [ip, port]
    end

    def default_supervisor_port(settings)
      settings.dig('supervisors', 0, 'port') ||
        site_options_class.new.to_h.dig('supervisors', 0, 'port')
    end

    def determine_site_class(settings)
      case site_type(settings)
      when 'tlc'
        RSMP::TLC::TrafficControllerSite
      else
        puts "Error: Unknown site type #{site_type(settings)}"
        exit
      end
    end

    def site_type(settings = nil)
      options[:type] || settings&.fetch('type', nil)
    end

    def run_site(site_class, settings, log_settings)
      Async do |task|
        task.annotate 'cli'
        loop do
          site = site_class.new(site_settings: settings, log_settings: log_settings)
          site.start
          site.wait
        rescue Psych::SyntaxError => e
          puts "Cannot read config file #{e}"
          break
        rescue RSMP::Schema::UnknownSchemaTypeError, RSMP::Schema::UnknownSchemaVersionError,
               RSMP::ConfigurationError => e
          puts "Cannot start site: #{e}"
          break
        rescue RSMP::Restart
          site.stop
        end
      end
    end

    def apply_supervisor_options(settings, log_settings)
      apply_basic_supervisor_options(settings)
      apply_version_options(settings)
      apply_log_options(log_settings)
    end

    def apply_basic_supervisor_options(settings)
      settings['site_id'] = options[:id] if options[:id]
      settings['ip'] = options[:ip] if options[:ip]
      settings['port'] = options[:port] if options[:port]
    end

    def apply_version_options(settings)
      return unless options[:core] || options[:sxls]

      sxls = parse_sxls(options[:sxls]) if options[:sxls]
      apply_version_overrides(settings['default'] ||= {}, sxls)
      (settings['sites'] || {}).each_value { |site_settings| apply_version_overrides(site_settings, sxls) }
    end

    def apply_version_overrides(settings, sxls)
      settings['core_version'] = options[:core] if options[:core]
      settings['sxls'] = sxls if sxls
    end

    def apply_log_options(log_settings)
      log_settings['path'] = options[:log] if options[:log]
      log_settings['json'] = options[:json] if options[:json]
    end

    def run_supervisor(settings, log_settings)
      Async do |task|
        task.annotate 'cli'
        supervisor = RSMP::Supervisor.new(supervisor_settings: settings, log_settings: log_settings)
        supervisor.start
        supervisor.wait
      rescue Psych::SyntaxError => e
        puts "Cannot read config file #{e}"
      rescue RSMP::Schema::UnknownSchemaTypeError, RSMP::Schema::UnknownSchemaVersionError,
             RSMP::ConfigurationError => e
        puts "Cannot start supervisor: #{e}"
      end
    end

    # avoid Thor returnin 0 on failures, see
    # https://github.com/coinbase/salus/pull/380/files
    def self.exit_on_failure?
      true
    end
    private_class_method :exit_on_failure?
  end
end
