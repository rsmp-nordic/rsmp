module RSMP
  class SiteProxyStub
    include RSMP::Distributor
    include RSMP::Logging
    attr_reader :task

    def initialize task
      @task = task
      initialize_distributor
      initialize_logging({log_settings:{'active'=>false}})
    end
  end
end