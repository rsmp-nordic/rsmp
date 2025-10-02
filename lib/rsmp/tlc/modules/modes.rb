# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Traffic controller modes, plans, and operating positions
      # Handles mode switching, plan selection, and traffic situation management
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

        # M0002 - Set current time plan
        def handle_m0002(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          if TrafficControllerSite.from_rsmp_bool?(arg['status'])
            switch_plan arg['timeplan'], source: 'forced'
          else
            switch_plan 0, source: 'startup' # TODO: use clock/calender
          end
        end

        # M0003 - Set traffic situation
        def handle_m0003(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          switch_traffic_situation arg['traficsituation'], source: 'forced'
        end

        # Helper: Switch traffic situation
        def switch_traffic_situation(situation)
          @traffic_situation = situation.to_i
          @traffic_situation_source = 'forced'
        end

        # M0007 - Set fixed time control
        def handle_m0007(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          set_fixed_time_control arg['status'], source: 'forced'
        end

        # S0001 - Signal group status
        def handle_s0001(_status_code, status_name = nil, _options = {})
          case status_name
          when 'signalgroupstatus'
            TrafficControllerSite.make_status format_signal_group_status
          when 'cyclecounter', 'basecyclecounter'
            TrafficControllerSite.make_status @cycle_counter.to_s
          when 'stage'
            TrafficControllerSite.make_status 0.to_s
          end
        end

        # S0002 - Detector logic status
        def handle_s0002(_status_code, status_name = nil, _options = {})
          case status_name
          when 'detectorlogicstatus'
            TrafficControllerSite.make_status @detector_logics.map { |dl| bool_to_digit(dl.value) }.join
          end
        end

        # S0003 - Input status
        def handle_s0003(_status_code, status_name = nil, _options = {})
          case status_name
          when 'inputstatus'
            TrafficControllerSite.make_status @inputs.actual_string
          when 'extendedinputstatus'
            TrafficControllerSite.make_status 0.to_s
          end
        end

        # S0004 - Output status
        def handle_s0004(_status_code, status_name = nil, _options = {})
          case status_name
          when 'outputstatus', 'extendedoutputstatus'
            TrafficControllerSite.make_status 0
          end
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

        # S0014 - Current signal program
        def handle_s0014(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @plan
          when 'source'
            TrafficControllerSite.make_status @plan_source
          end
        end

        # S0015 - Current traffic situation
        def handle_s0015(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @traffic_situation
          when 'source'
            TrafficControllerSite.make_status @traffic_situation_source
          end
        end

        # S0016 - Number of detector logics
        def handle_s0016(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @detector_logics.size
          end
        end

        # S0017 - Number of signal groups
        def handle_s0017(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @signal_groups.size
          end
        end

        # S0018 - Number of time plans
        def handle_s0018(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @plans.size
          end
        end

        # S0019 - Number of traffic situations
        def handle_s0019(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @num_traffic_situations
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

        # S0021 - Detector logic forcing status
        def handle_s0021(_status_code, status_name = nil, _options = {})
          case status_name
          when 'detectorlogics'
            TrafficControllerSite.make_status @detector_logics.map { |logic| bool_to_digit(logic.forced) }.join
          end
        end

        # S0022 - List of time plans
        def handle_s0022(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @plans.keys.join(',')
          end
        end

        # S0023 - Dynamic bands
        def handle_s0023(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            dynamic_bands = @plans.map { |_nr, plan| plan.dynamic_bands_string }
            str = dynamic_bands.compact.join(',')
            TrafficControllerSite.make_status str
          end
        end

        # S0024 - Offset times
        def handle_s0024(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status '1-0'
          end
        end

        # S0026 - Week time table
        def handle_s0026(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status '0-00'
          end
        end

        # S0027 - Time tables
        def handle_s0027(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            status = @day_time_table.map do |i, item|
              "#{i}-#{item[:plan]}-#{item[:hour]}-#{item[:min]}"
            end.join(',')
            TrafficControllerSite.make_status status
          end
        end

        # S0028 - Cycle time
        def handle_s0028(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            times = @plans.map do |_nr, plan|
              "#{format('%02d', plan.number)}-#{format('%02d', plan.cycle_time)}"
            end.join(',')
            TrafficControllerSite.make_status times
          end
        rescue StandardError => e
          puts e
        end

        # S0029 - Forced input status
        def handle_s0029(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @inputs.forced_string
          end
        end

        # S0030 - Forced output status
        def handle_s0030(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status ''
          end
        end

        # S0031 - Trigger level sensitivity for loop detector
        def handle_s0031(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status ''
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

        # S0033 - Signal priority status
        def handle_s0033(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status get_priority_list
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
