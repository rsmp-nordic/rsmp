# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Signal groups and signal priority management
      # Handles signal group status and priority requests
      module SignalGroups
        # M0022 - Signal priority request
        def handle_m0022(arg, _options = {})
          id = arg['requestId']
          type = arg['type']
          priority = @signal_priorities.find { |priority| priority.id == id }
          case type
          when 'new'
            raise MessageRejected, "Priority Request #{id} already exists" if priority

            # ref = arg.slice('signalGroupId','inputId','connectionId','approachId','laneInId','laneOutId')
            signal_group = node.find_component arg['signalGroupId'] if arg['signalGroupId']

            level = arg['level']
            eta = arg['eta']
            vehicle_type = arg['vehicleType']
            @signal_priorities << SignalPriority.new(node: self, id: id, level: level, eta: eta,
                                                     vehicle_type: vehicle_type)
            log "Priority request #{id} for signal group #{signal_group.c_id} received.", level: :info

          when 'update'
            raise MessageRejected, "Cannot update priority request #{id}, not found" unless priority

            log "Updating Priority Request #{id}", level: :info

          when 'cancel'
            raise MessageRejected, "Cannot cancel priority request #{id}, not found" unless priority

            priority.cancel
            log "Priority request with id #{id} cancelled.", level: :info

          else
            raise MessageRejected, "Unknown type #{type}"
          end
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

        # S0017 - Number of signal groups
        def handle_s0017(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @signal_groups.size
          end
        end

        # S0033 - Signal priority status
        def handle_s0033(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status get_priority_list
          end
        end
      end
    end
  end
end
