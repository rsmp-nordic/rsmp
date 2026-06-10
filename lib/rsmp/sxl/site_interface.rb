module RSMP
  module SXL
    # SXL interface used by a site-side proxy.
    class SiteInterface < Interface
      def process_message(message)
        proxy.process_sxl_request message
      end
    end
  end
end
