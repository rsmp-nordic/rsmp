# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Operating modes and functional positions for traffic controllers
      # Handles mode switching (NormalControl/YellowFlash/Dark) and control modes
      module Modes
        # M0001 - Set functional position
        def handle_m0001(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']

          # timeout is specified in minutes, but we take 1 to mean 1s
          # this is not according to the curent rsmp spec, but is done
          # to speed up testing
          timeout = arg['timeout'].to_i
          if timeout == 1
            timeout = 1
          else
            timeout *= 60
          end

          switch_functional_position arg['status'],
                                     timeout: timeout,
                                     source: 'forced'
        end

        # M0007 - Set fixed time control
        def handle_m0007(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          set_fixed_time_control arg['status'], source: 'forced'
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

        # S0007 - Intersection status
        def handle_s0007(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @function_position != 'Dark'
          when 'source'
            TrafficControllerSite.make_status @function_position_source
          end
        end

        # S0008 - Manual control status
        def handle_s0008(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @manual_control
          when 'source'
            TrafficControllerSite.make_status @manual_control_source
          end
        end

        # S0009 - Fixed time control status
        def handle_s0009(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @fixed_time_control
          when 'source'
            TrafficControllerSite.make_status @fixed_time_control_source
          end
        end

        # S0010 - Isolated control status
        def handle_s0010(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @isolated_control
          when 'source'
            TrafficControllerSite.make_status @isolated_control_source
          end
        end

        # S0011 - Yellow flash status
        def handle_s0011(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool(@function_position == 'YellowFlash')
          when 'source'
            TrafficControllerSite.make_status @function_position_source
          end
        end

        # S0012 - All red status
        def handle_s0012(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @all_red
          when 'source'
            TrafficControllerSite.make_status @all_red_source
          end
        end

        # S0013 - Police key status
        def handle_s0013(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @police_key
          end
        end

        # S0020 - Control mode
        def handle_s0020(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'controlmode'
            TrafficControllerSite.make_status @control_mode
          end
        end

        # S0032 - Coordination status
        def handle_s0032(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status 'local'
          when 'source'
            TrafficControllerSite.make_status @intersection_source
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
      end
    end
  end
end
