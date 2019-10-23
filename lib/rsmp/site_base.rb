# Things shared between sites and site proxies

module RSMP
  module SiteBase
    attr_reader :aggregated_status, :aggregated_status_bools

    def initialize_site
      @aggregated_status = {}
      @aggregated_status_bools = Array.new(8,false)
    end
  end
end