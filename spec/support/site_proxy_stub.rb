module RSMP
  class SiteProxyStub
    include RSMP::Notifier
    include RSMP::Logging

    def initialize
      initialize_distributor
      initialize_logging({})
    end

    def self.async &block
      error = nil
       Async do |task|
        proxy = self.new
        yield task, proxy

      # catch error and reraise outside async block
      # we do this to avoid async printing the errors to the console,
      # which inteferres with rspec output
      rescue StandardError => e
        error = e
        task.stop
      end.wait
      raise error if error
    end
  end
end