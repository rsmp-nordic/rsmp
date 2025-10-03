# frozen_string_literal: true

module RSMP
  class Collector
    # Logging methods for collectors
    module Logging
      # log when we start collecting
      def log_start
        @distributor.log "#{identifier}: Waiting for #{describe_matcher}".strip, level: :collect
      end

      # log current progress
      def log_incomplete
        @distributor.log "#{identifier}: #{describe_progress}", level: :collect
      end

      # log when we end collecting
      def log_complete
        @distributor.log "#{identifier}: Done", level: :collect
      end
    end
  end
end
