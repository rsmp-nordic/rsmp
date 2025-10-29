module RSMP
  module TLC
    class TrafficControllerSite < Site
      # Configuration options for traffic controller sites.
      class Options < RSMP::Site::Options
        def schema_file
          'traffic_controller_site.json'
        end
      end
    end
  end
end
