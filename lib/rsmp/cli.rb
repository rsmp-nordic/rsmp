require 'thor'
require 'rsmp'

module RSMP
  class CLI < Thor
    desc "version", "Show version"
    def version
      puts RSMP::VERSION
    end

    desc "site", "Run RSMP site"
    method_option :config, :type => :string, :aliases => "-c", banner: 'Path to .yaml config file'
    method_option :id, :type => :string, :aliases => "-i", banner: 'RSMP site id'
    method_option :supervisors, :type => :string, :aliases => "-s", banner: 'ip:port,... list of supervisor to connect to'
    method_option :log, :type => :string, :aliases => "-l", banner: 'Path to log file'
    method_option :json, :type => :boolean, :aliases => "-j", banner: 'Show JSON messages in log'
    method_option :type, :type => :string, :aliases => "-t", banner: 'Type of site: [tlc]'
    def site
      settings = {}
      log_settings = { 'active' => true }

      if options[:config]
        if File.exist? options[:config]
          settings = YAML.load_file options[:config]
          log_settings = settings.delete('log') || {}
        else
          puts "Error: Config #{options[:config]} not found"
          exit
        end
      end

      if options[:id]
        settings['site_id'] = options[:id]
      end

      if options[:supervisors]
        settings['supervisors'] = []
        options[:supervisors].split(',').each do |supervisor|
          ip, port = supervisor.split ':'
          ip = '127.0.0.1' if ip.empty?
          port = '12111' if port.empty?
          settings['supervisors'] << {"ip"=>ip, "port"=>port}
        end
      end

      if options[:log]
        log_settings['path'] = options[:log]
      end

      if options[:json]
        log_settings['json'] = options[:json]
      end

      site_class = RSMP::Site
      if options[:type]
        case options[:type]
          when 'tlc'
            site_class = RSMP::TLC::TrafficControllerSite
          else
            site_class = RSMP::Site
        end
      end
      Async do |task|
        task.annotate 'cli'
        loop do
          begin
            site = site_class.new(site_settings:settings, log_settings: log_settings)
            site.start
            site.wait
          rescue RSMP::Restart
            site.stop
          end
        end
      end
    rescue Interrupt
      # cntr-c pressed
    rescue SignalException
      # SIGTERM received
    rescue exit
      # exit() called in code
    rescue RSMP::Schema::UnknownSchemaTypeError => e
      puts "Cannot start site: #{e}"
    rescue RSMP::Schema::UnknownSchemaVersionError => e
      puts "Cannot start site: #{e}"
    rescue Psych::SyntaxError => e
      puts "Cannot read config file #{e}"
    rescue Exception => e
      puts "Uncaught error: #{e}"
      puts caller.join("\n")
    end

    desc "supervisor", "Run RSMP supervisor"
    method_option :config, :type => :string, :aliases => "-c", banner: 'Path to .yaml config file'
    method_option :id, :type => :string, :aliases => "-i", banner: 'RSMP site id'
    method_option :ip, :type => :numeric, banner: 'IP address to listen on'
    method_option :port, :type => :string, :aliases => "-p", banner: 'Port to listen on'
    method_option :log, :type => :string, :aliases => "-l", banner: 'Path to log file'
    method_option :json, :type => :boolean, :aliases => "-j", banner: 'Show JSON messages in log'
    def supervisor
      settings = {}
      log_settings = { 'active' => true }

      if options[:config]
        if File.exist? options[:config]
          settings = YAML.load_file options[:config]
          log_settings = settings.delete 'log'
        else
          puts "Error: Config #{options[:config]} not found"
          exit
        end
      end

      if options[:id]
        settings['site_id'] = options[:id]
      end

      if options[:ip]
        settings['ip'] = options[:ip]
      end

      if options[:port]
        settings['port'] = options[:port]
      end

      if options[:log]
        log_settings['path'] = options[:log]
      end

      if options[:json]
        log_settings['json'] = options[:json]
      end

      Async do |task|
        task.annotate 'cli'
        supervisor = RSMP::Supervisor.new(supervisor_settings:settings,log_settings:log_settings)
        supervisor.start
        supervisor.wait
      end
    rescue Interrupt
      # ctrl-c
    rescue RSMP::ConfigurationError => e
      puts "Cannot start supervisor: #{e}"
    end

    desc "convert", "Convert SXL from YAML to JSON Schema"
    method_option :in, :type => :string, :aliases => "-i", banner: 'Path to YAML input file'
    method_option :out, :type => :string, :aliases => "-o", banner: 'Path to JSON Schema output file'
    def convert
      unless options[:in]
        puts "Error: Input option missing"
        exit
      end

      unless options[:out]
        puts "Error: Output option missing"
        exit
      end

      unless File.exist? options[:in]
        puts "Error: Input path file #{options[:in]} not found"
        exit
      end

      sxl = RSMP::Convert::Import::YAML.read options[:in]
      RSMP::Convert::Export::JSONSchema.write sxl, options[:out]
    end

    # avoid Thor returnin 0 on failures, see
    # https://github.com/coinbase/salus/pull/380/files
    def self.exit_on_failure?
      true
    end
  end
end