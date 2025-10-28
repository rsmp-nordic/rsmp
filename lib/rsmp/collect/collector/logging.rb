module RSMP
  class Collector
    module Logging
      def log_start
        @distributor.log "#{identifier}: Waiting for #{describe_matcher}".strip, level: :collect
      end

      def log_incomplete
        @distributor.log "#{identifier}: #{describe_progress}", level: :collect
      end

      def log_complete
        @distributor.log "#{identifier}: Done", level: :collect
      end
    end
  end
end
