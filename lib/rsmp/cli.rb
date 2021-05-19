require 'thor'
require 'rsmp'

module RSMP
  class CLI < Thor

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
        options[:supervisors].split(',').each do |supervisor|
          settings[:supervisors] ||= []
          ip, port = supervisor.split ':'
          ip = '127.0.0.1' if ip.empty?
          port = '12111' if port.empty?
          settings[:supervisors] << {"ip"=>ip, "port"=>port}
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
            site_class = RSMP::Tlc
          else
            site_class = RSMP::Site
        end
      end
      site_class.new(site_settings:settings, log_settings: log_settings).start
    rescue RSMP::Schemer::UnknownSchemaTypeError => e
      puts "Cannot start site: #{e}"
    rescue RSMP::Schemer::UnknownSchemaVersionError => e
      puts "Cannot start site: #{e}"
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

      RSMP::Supervisor.new(supervisor_settings:settings,log_settings:log_settings).start
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

  end
end