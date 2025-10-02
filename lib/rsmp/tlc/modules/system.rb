# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # System-level commands and status for traffic controllers
      # Handles restart, emergency routes, security, clock, version, and configuration
      module System
        # M0004 - Restart traffic light controller
        def handle_m0004(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          # don't restart immeediately, since we need to first send command response
          # instead, defer an action, which will be handled by the TLC site
          log 'Sheduling restart of TLC', level: :info
          @node.defer :restart
        end

        # M0005 - Enable/disable emergency route
        def handle_m0005(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          route = arg['emergencyroute'].to_i
          enable = (arg['status'] == 'True')
          @last_emergency_route = route

          if enable
            if @emergency_routes.add? route
              log "Enabling emergency route #{route}", level: :info
            else
              log "Emergency route #{route} already enabled", level: :info
            end
          elsif @emergency_routes.delete? route
            log "Disabling emergency route #{route}", level: :info
          else
            log "Emergency route #{route} already disabled", level: :info
          end
        end

        # M0103 - Set security code
        def handle_m0103(arg, _options = {})
          level = { 'Level1' => 1, 'Level2' => 2 }[arg['status']]
          @node.change_security_code level, arg['oldSecurityCode'], arg['newSecurityCode']
        end

        # M0104 - Set clock
        def handle_m0104(arg, _options = {})
          @node.verify_security_code 1, arg['securityCode']
          time = Time.new(
            arg['year'],
            arg['month'],
            arg['day'],
            arg['hour'],
            arg['minute'],
            arg['second'],
            'UTC'
          )
          clock.set time
          log "Clock set to #{time}, (adjustment is #{clock.adjustment}s)", level: :info
        end

        # S0005 - Traffic controller starting
        def handle_s0005(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @is_starting
          when 'statusByIntersection' # from sxl 1.2.0
            TrafficControllerSite.make_status([
                                                {
                                                  'intersection' => '1',
                                                  'startup' => TrafficControllerSite.to_rmsp_bool(@is_starting)
                                                }
                                              ])
          end
        end

        # S0006 - Emergency route status (deprecated, use S0035)
        def handle_s0006(_status_code, status_name = nil, options = {})
          if Proxy.version_meets_requirement? options[:sxl_version],
                                              '>=1.2.0'
            log 'S0006 is depreciated, use S0035 instead.',
                level: :warning
          end
          status = @emergency_routes.any?
          case status_name
          when 'status'
            TrafficControllerSite.make_status status
          when 'emergencystage'
            TrafficControllerSite.make_status status ? @last_emergency_route : 0
          end
        end

        # S0035 - Emergency routes (replaces S0006)
        def handle_s0035(_status_code, status_name = nil, _options = {})
          case status_name
          when 'emergencyroutes'
            list = @emergency_routes.sort.map { |route| { 'id' => route.to_s } }
            TrafficControllerSite.make_status list
          end
        end

        # S0095 - Version information
        def handle_s0095(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status RSMP::VERSION
          end
        end

        # S0096 - Current date and time
        def handle_s0096(_status_code, status_name = nil, _options = {})
          now = clock.now
          case status_name
          when 'year'
            TrafficControllerSite.make_status now.year.to_s.rjust(4, '0')
          when 'month'
            TrafficControllerSite.make_status now.month.to_s.rjust(2, '0')
          when 'day'
            TrafficControllerSite.make_status now.day.to_s.rjust(2, '0')
          when 'hour'
            TrafficControllerSite.make_status now.hour.to_s.rjust(2, '0')
          when 'minute'
            TrafficControllerSite.make_status now.min.to_s.rjust(2, '0')
          when 'second'
            TrafficControllerSite.make_status now.sec.to_s.rjust(2, '0')
          end
        end

        # S0097 - Configuration checksum
        def handle_s0097(_status_code, status_name = nil, _options = {})
          case status_name
          when 'checksum'
            TrafficControllerSite.make_status '1'
          when 'timestamp'
            now = clock.to_s
            TrafficControllerSite.make_status now
          end
        end

        # S0098 - Configuration data
        def handle_s0098(_status_code, status_name = nil, _options = {})
          settings = node.site_settings.slice('components', 'signal_plans', 'inputs', 'startup_sequence')
          json = JSON.generate(settings)
          case status_name
          when 'config'
            TrafficControllerSite.make_status json
          when 'timestamp'
            now = clock.to_s
            TrafficControllerSite.make_status now
          when 'version'
            TrafficControllerSite.make_status Digest::MD5.hexdigest(json)
          end
        end
      end
    end
  end
end
