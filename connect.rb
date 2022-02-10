require_relative 'lib/rsmp'

client_thread = Thread.new do
  Async do
    site = RSMP::Site.new log_settings: {'prefix' => 'site      ' } 
    site.start
    site.wait
  end
end

server_thread = Thread.new do
  Async do
    delay = 3
    puts "supervisor: initial delay of #{delay}s"
    sleep delay
    supervisor = RSMP::Supervisor.new log_settings: {'prefix' => 'supervisor' } 
    supervisor.start
    supervisor.wait_for_site :any, timeout: 5
    puts "supervisor: site connected"
    exit
  rescue RSMP::TimeoutError
    puts "supervisor: timeout"
    exit 1
  end
end

server_thread.join