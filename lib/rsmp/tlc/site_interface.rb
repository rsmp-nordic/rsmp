module RSMP
  # Traffic Light Controller SXL support.
  module TLC
    # Site-side TLC SXL interface.
    class SiteInterface < RSMP::SXL::SiteInterface
    end

    RSMP::SXL::Registry.register_interface SiteInterface
  end
end
