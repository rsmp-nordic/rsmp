require 'thor'
require 'rsmp'

module RSMP
	class CLI < Thor

		desc "site", "Run RSMP site"
		method_option :config, :type => :string, :aliases => "-c", banner: 'Path to .yaml config file'
		method_option :id, :type => :string, :aliases => "-i", banner: 'RSMP site id'
		method_option :supervisors, :type => :string, :aliases => "-s", banner: 'ip:port,... list of supervisor to connect to'			
		def site
			converted = {
					site_settings_path: options[:config],
					site_settings: {
						site_id: options[:id],
					}
			}
			
  		if options[:supervisors]
	  		options[:supervisors].split(',').each do |supervisor|
	  			converted[:site_settings][:supervisors] ||= []
					ip, port = supervisor.split ':'
					ip = '127.0.0.1' if ip.empty?
					port = '12111' if port.empty?
					converted[:site_settings][:supervisors] << {"ip"=>ip, "port"=>port}
				end
			end

			converted[:site_settings].compact!
			RSMP::Site.new(converted).start
		end

		desc "supervisor", "Run RSMP supervisor"
		method_option :config, :type => :string, :aliases => "-c", banner: 'Path to .yaml config file'
		method_option :id, :type => :string, :aliases => "-i", banner: 'RSMP site id'
		method_option :ip, :type => :numeric, banner: 'IP address to listen on'			
		method_option :port, :type => :string, :aliases => "-p", banner: 'Port to listen on'
		def supervisor
			converted = {
					supervisor_settings_path: options[:config],
					supervisor_settings: {
						site_id: options[:id],
						ip: options[:ip],
						port: options[:port]
					}
			}
			converted[:supervisor_settings].compact!
			RSMP::Supervisor.new(converted).start
		end

	end
end