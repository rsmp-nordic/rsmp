require 'async'
require 'async/condition'
require 'io/endpoint'
require 'io/endpoint/host_endpoint'
# Custom timeout error to match RSMP
class TimeoutError < StandardError; end

# Minimal reproduction of wait_for_site hanging issue
class MinimalSupervisor
  attr_reader :site_condition, :proxies

  def initialize
    @proxies = []
    @site_condition = Async::Condition.new
  end

  def start
    puts "Starting supervisor on port 12111"
    @endpoint = IO::Endpoint.tcp('0.0.0.0', 12111)
    
    @accept_task = Async::Task.current.async do |task|
      task.annotate "accept connections"
      @endpoint.accept do |socket|
        handle_connection(socket)
      end
    end
  end

  def handle_connection(socket)
    remote_info = {
      ip: socket.remote_address.ip_address,
      port: socket.remote_address.ip_port
    }
    
    puts "Connection from #{remote_info[:ip]}:#{remote_info[:port]}"
    
    # Simulate creating a proxy
    proxy = "site_proxy_#{@proxies.length}"
    @proxies << proxy
    
    # This should signal waiting tasks
    site_ids_changed
    
    # Keep connection open briefly
    sleep 0.1
  ensure
    socket&.close
  end

  def site_ids_changed
    puts "Signaling site_condition"
    @site_condition.signal
  end

  def find_site(site_id)
    return @proxies.first if site_id == :any && @proxies.any?
    nil
  end

  # Replicate the exact wait_for_condition pattern from RSMP::Task
  def wait_for_condition(condition, timeout:, task: Async::Task.current, &block)
    unless task
      raise RuntimeError.new("Can't wait without a task")
    end
    
    # This is the key line that was highlighted - task.with_timeout(timeout)
    task.with_timeout(timeout) do
      while task.running?
        value = condition.wait
        return value unless block
        result = yield value
        return result if result
      end
      raise RuntimeError.new("Can't wait for condition because task #{task.object_id} #{task.annotation} is not running")
    end
  rescue Async::TimeoutError
    raise TimeoutError.new
  end

  def wait_for_site(site_id, timeout:)
    site = find_site(site_id)
    return site if site

    puts "Waiting for site with timeout #{timeout}s"
    
    # Use the same pattern as the real RSMP code
    wait_for_condition(@site_condition, timeout: timeout) do
      result = find_site(site_id)
      puts "Condition check: found=#{!!result}"
      result
    end
  end

  def stop
    @accept_task&.stop
  end
end

# Test the pattern
Async do |task|
  supervisor = MinimalSupervisor.new
  
  # Start supervisor
  supervisor_task = task.async do |t|
    t.annotate "supervisor"
    supervisor.start
  end
  
  # Wait for supervisor to be ready
  sleep 0.1
  
  # Test wait_for_site (this is where hanging occurs)
  wait_task = task.async do |t|
    t.annotate "wait_for_site test"
    begin
      result = supervisor.wait_for_site(:any, timeout: 5.0)
      puts "wait_for_site succeeded: #{result}"
    rescue TimeoutError
      puts "wait_for_site timed out"
    rescue => e
      puts "wait_for_site failed: #{e.class} - #{e.message}"
    end
  end
  
  # Simulate client connection to trigger site_ids_changed
  client_task = task.async do |t|
    t.annotate "client connection"
    sleep 0.5  # Give wait_for_site time to start waiting
    
    begin
      puts "Client connecting to port 12111"
      endpoint = IO::Endpoint.tcp('127.0.0.1', 12111)
      endpoint.connect do |socket|
        puts "Client connected successfully"
        sleep 0.2  # Keep connection open
      end
      puts "Client disconnected"
    rescue => e
      puts "Client connection failed: #{e.class} - #{e.message}"
    end
  end
  
  # Wait for all tasks
  [wait_task, client_task].each(&:wait)
  supervisor.stop
  
  puts "Test completed"
end
