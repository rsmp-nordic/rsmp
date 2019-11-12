#
# RSMP base class
#

module RSMP
  class Base
    attr_reader :archive, :logger

    def initialize options
      @archive = options[:archive] || RSMP::Archive.new
      @logger = options[:logger] || RSMP::Logger.new(options[:log_settings]) 
    end

    def author
    end

    def log str, options={}
      default = { level: :log, author: author }
      prepared = RSMP::Archive.prepare_item default.merge(options.merge str: str)
      @archive.add prepared
      @logger.log prepared
      prepared
    end

  end
end