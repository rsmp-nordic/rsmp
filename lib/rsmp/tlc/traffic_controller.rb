require 'fileutils'

require_relative 'traffic_controller/extensions/state'
require_relative 'traffic_controller/extensions/cycle'
require_relative 'traffic_controller/extensions/outputs'
require_relative 'traffic_controller/extensions/commands'
require_relative 'traffic_controller/extensions/status'

module RSMP
  module TLC
    class TrafficController < Component
      include TrafficControllerExtensions::State
      include TrafficControllerExtensions::Cycle
      include TrafficControllerExtensions::Outputs
      include TrafficControllerExtensions::Commands
      include TrafficControllerExtensions::Status

      attr_reader :pos, :cycle_time, :plan, :cycle_counter,
                  :functional_position,
                  :startup_sequence_active, :startup_sequence, :startup_sequence_pos

      def initialize(node:, id:, signal_plans:, startup_sequence:, **options)
        live_output = options.delete(:live_output)
        inputs = options.delete(:inputs)

        super(node: node, id: id, **options.merge(grouped: true))
        @signal_groups = []
        @detector_logics = []
        @plans = signal_plans
        @num_traffic_situations = 1

        configure_inputs(inputs)

        @startup_sequence = startup_sequence
        @live_output = live_output
        reset
      end

      private

      def configure_inputs(input_settings)
        settings = input_settings || {}
        num_inputs = settings['total']
        @input_programming = settings['programming']
        @inputs = TLC::Inputs.new(num_inputs || 8)
      end
    end
  end
end
