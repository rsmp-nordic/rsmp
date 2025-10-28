module RSMP
  class Collector
    # Status predicate methods for collectors
    module Status
      def collecting?
        @status == :collecting
      end

      def ok?
        @status == :ok
      end

      def timeout?
        @status == :timeout
      end

      def ready?
        @status == :ready
      end

      def cancelled?
        @status == :cancelled
      end

      def ingoing?
        @ingoing == true
      end

      def outgoing?
        @outgoing == true
      end
    end
  end
end
