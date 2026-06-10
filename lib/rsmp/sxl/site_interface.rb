module RSMP
  module SXL
    class SiteInterface < Interface
      def process_message(message)
        proxy.process_sxl_request message
      end
    end
  end
end
