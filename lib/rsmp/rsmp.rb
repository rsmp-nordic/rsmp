# rsmp module

require_relative 'logger'

module RSMP
  WRAPPING_DELIMITER = "\f"

  def self.now_object
    # date using UTC time zone
    Time.now.utc
  end

  def self.now_object_to_string now
    # date in the format required by rsmp, using UTC time zone
    # example: 2015-06-08T12:01:39.654Z
    time ||= now.utc
    time.strftime("%FT%T.%3NZ")
  end

  def self.now_string time=nil
    time ||= Time.now
    now_object_to_string time
  end

  def self.parse_time time_str
    Time.parse time_str
  end
  
  def self.log_prefix ip
    "#{now_string} #{ip.ljust(20)}"
  end

end