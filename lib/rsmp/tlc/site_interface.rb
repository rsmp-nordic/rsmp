module RSMP
  module TLC
    class SiteInterface < RSMP::SXL::SiteInterface
    end

    RSMP::SXL::Registry.register_interface SiteInterface
  end
end
