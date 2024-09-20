module RSMP
  class SiteProxyStub
    include RSMP::Distributor
    include RSMP::Logging
    attr_reader :task, :core_version

    def initialize core_version, task
      @task = task
      @core_version = core_version
      initialize_distributor
      initialize_logging({log_settings:{'active'=>false}})
    end
  end
end