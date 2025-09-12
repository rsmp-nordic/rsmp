require 'async'
require 'async/condition'
require 'io/endpoint'
require 'io/endpoint/host_endpoint'

# Custom timeout error to match RSMP
class TimeoutError < StandardError; end

# Minimal reproduction of wait_for_site hanging issue
class MinimalSupervisor
  attr_reader :site_condition, :proxies, :ready_condition

  def initialize
    @proxies = []
    @site_condition = Async::Condition.new
    @ready_condition = Async::Condition.new
    @server_ready = false
    @server_task = nil
  end

  def start
    puts "Starting supervisor on port 12111"
    @endpoint = IO::Endpoint.tcp('0.0.0.0', 12111)
    
    @server_task = Async::Task.current.async do |task|
      task.annotate "supervisor server"
      
      # Bind the server socket
      @endpoint.bind do |server|
        puts "Server bound to port"
        @server_ready = true
        @ready_condition.signal
        
        # Accept connections in a loop
        loop do
          puts "Waiting for connections..."
          peer, address = server.accept
          
          # Handle each connection in its own task to avoid blocking
          task.async do |connection_task|
            connection_task.annotate "handle connection"
            handle_connection(peer)
          end
        end
      end
    rescue => e
      puts "Server error: #{e.class} - #{e.message}"
      puts e.backtrace.first(3)
    end
  end

  def ready?
    @server_ready
  end

  def wait_until_ready(timeout: 5)
    return if ready?
    
    puts "Waiting for server to be ready..."
    wait_for_condition(@ready_condition, timeout: timeout) do
      ready?
    end
  end

  def handle_connection(socket)
    remote_info = {
      ip: socket.remote_address.ip_address,
      port: socket.remote_address.ip_port
    }
    
    puts "Connection from #{remote_info[:ip]}:#{remote_info[:port]}"
    
    # Simulate the real RSMP handshake delay
    sleep(0.05)
    
    # Simulate creating a proxy (this is what triggers the condition)
    proxy = "site_proxy_#{@proxies.length}"
    @proxies << proxy
    
    puts "Created proxy: #{proxy} (total: #{@proxies.length})"
    
    # This should signal waiting tasks - but there might be a race condition
    site_ids_changed
    
    # Keep connection open briefly to simulate real behavior
    sleep 0.1
  ensure
    socket&.close
    puts "Connection closed"
  end

  def site_ids_changed
    puts "Signaling site_condition (#{@proxies.length} proxies)"
    @site_condition.signal(@proxies.dup)  # Signal with current proxy list
  end

  def find_site(site_id)
    result = @proxies.first if site_id == :any && @proxies.any?
    puts "find_site(#{site_id}): #{result ? 'found' : 'not found'} (#{@proxies.length} proxies)"
    result
  end

  # Replicate the EXACT wait_for_condition pattern from RSMP::Task
  def wait_for_condition(condition, timeout:, task: Async::Task.current, &block)
    unless task
      raise RuntimeError.new("Can't wait without a task")
    end
    
    puts "wait_for_condition starting (task: #{task.object_id})"
    
    task.with_timeout(timeout) do
      iteration = 0
      while task.running?
        iteration += 1
        puts "wait_for_condition iteration #{iteration}"
        
        # Check condition BEFORE waiting (this is crucial)
        if block
          result = yield
          if result
            puts "wait_for_condition succeeded immediately on iteration #{iteration}: #{result}"
            return result
          end
        end
        
        puts "About to wait on condition..."
        value = condition.wait  # This is where it might hang
        puts "Condition signaled with value: #{value.inspect}"
        
        # Check condition AFTER being signaled
        if block
          result = yield value
          if result
            puts "wait_for_condition succeeded after signal: #{result}"
            return result
          else
            puts "Condition check after signal returned false/nil"
          end
        else
          return value
        end
      end
      raise RuntimeError.new("Can't wait for condition because task is not running")
    end
  rescue Async::TimeoutError => e
    puts "wait_for_condition timed out after #{timeout}s"
    raise TimeoutError.new
  end

  def wait_for_site(site_id, timeout:)
    puts "wait_for_site called for #{site_id} with timeout #{timeout}s"
    
    # Check immediately first (like the real code does)
    site = find_site(site_id)
    if site
      puts "Site found immediately: #{site}"
      return site
    end

    puts "No site found immediately, waiting..."
    
    # Use the same pattern as the real RSMP code
    wait_for_condition(@site_condition, timeout: timeout) do |signaled_value|
      puts "Checking condition in wait_for_site block (signaled_value: #{signaled_value.inspect})"
      result = find_site(site_id)
      puts "find_site returned: #{result.inspect}"
      result
    end
  end

  def stop
    puts "Stopping supervisor"
    @server_task&.stop
  end
end

# Test with more realistic timing to reproduce the race condition
puts "Starting test on #{RUBY_PLATFORM}"
puts "Ruby version: #{RUBY_VERSION}"

Async do |task|
  supervisor = MinimalSupervisor.new
  
  # Start supervisor in background
  supervisor_task = task.async do |t|
    t.annotate "supervisor"
    supervisor.start
  end
  
  # Wait for supervisor to be truly ready
  puts "Waiting for supervisor to be ready..."
  supervisor.wait_until_ready(timeout: 5)
  puts "Supervisor is ready, proceeding with test"
  
  # Add a small delay to let the server settle
  sleep 0.1
  
  # Start the wait_for_site task FIRST (this is key to reproducing the race)
  wait_task = task.async do |t|
    t.annotate "wait_for_site"
    puts "Starting wait_for_site task"
    begin
      result = supervisor.wait_for_site(:any, timeout: 2.0)  # Shorter timeout to see failure faster
      puts "SUCCESS: wait_for_site returned: #{result}"
    rescue TimeoutError => e
      puts "TIMEOUT: wait_for_site timed out"
      raise e
    rescue => e
      puts "ERROR: wait_for_site failed: #{e.class} - #{e.message}"
      puts e.backtrace.first(5)
      raise e
    end
  end
  
  # Give wait_for_site time to start and begin waiting
  sleep 0.2
  
  # Now connect (this should trigger the signal)
  client_task = task.async do |t|
    t.annotate "client"
    puts "Client task starting connection"
    
    # Add platform-specific delay before connecting
    if RUBY_PLATFORM.match?(/cygwin|mswin|mingw/)
      puts "Windows detected, adding extra delay"
      sleep 0.3
    end
    
    begin
      puts "Client connecting to 127.0.0.1:12111"
      endpoint = IO::Endpoint.tcp('127.0.0.1', 12111)
      endpoint.connect do |socket|
        puts "Client connected successfully"
        # Keep connection open longer on Windows
        connection_time = RUBY_PLATFORM.match?(/cygwin|mswin|mingw/) ? 0.5 : 0.2
        sleep connection_time
        puts "Client maintaining connection for #{connection_time}s"
      end
      puts "Client connection closed normally"
    rescue => e
      puts "Client connection failed: #{e.class} - #{e.message}"
      puts e.backtrace.first(3)
      raise e
    end
  end
  
  # Wait for both tasks with a reasonable timeout
  puts "Waiting for tasks to complete..."
  begin
    Async::Task.current.with_timeout(10) do
      wait_task.wait
      client_task.wait
    end
    puts "All tasks completed successfully"
  rescue Async::TimeoutError
    puts "OVERALL TIMEOUT: Test timed out after 10s"
    puts "wait_task status: #{wait_task.status}"
    puts "client_task status: #{client_task.status}"
  rescue => e
    puts "Test failed with error: #{e.class} - #{e.message}"
  ensure
    supervisor.stop
    puts "Test cleanup completed"
  end
end

puts "Script finished"