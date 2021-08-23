require_relative 'ezpool/version'
require_relative 'ezpool/timed_stack'
require_relative 'ezpool/errors'
require_relative 'ezpool/connection_manager'

require 'set'


# Generic connection pool class for e.g. sharing a limited number of network connections
# among many threads.  Note: Connections are lazily created.
#
# Example usage with block (faster):
#
#    @pool = EzPool.new { Redis.new }
#
#    @pool.with do |redis|
#      redis.lpop('my-list') if redis.llen('my-list') > 0
#    end
#
# Using optional timeout override (for that single invocation)
#
#    @pool.with(timeout: 2.0) do |redis|
#      redis.lpop('my-list') if redis.llen('my-list') > 0
#    end
#
# Example usage replacing an existing connection (slower):
#
#    $redis = EzPool.wrap { Redis.new }
#
#    def do_work
#      $redis.lpop('my-list') if $redis.llen('my-list') > 0
#    end
#
# Note that there's no way to pass a disconnection function to this
# usage, nor any way to guarantee that subsequent calls will go to the
# same connection (if your connection has any concept of sessions, this
# may be important). We strongly recommend against using wrapped
# connections in production environments.
#
# Accepts the following options:
# - :size - number of connections to pool, defaults to 5
# - :timeout - amount of time to wait for a connection if none currently available, defaults to 5 seconds
# - :max_age - maximum number of seconds that a connection may be alive for (will recycle on checkin/checkout)
# - :connect_with - callable for creating a connection
# - :disconnect_with - callable for shutting down a connection
#
class EzPool
  DEFAULTS = {size: 5, timeout: 1, max_age: Float::INFINITY}

  def self.wrap(options, &block)
    if block_given?
      options[:connect_with] = block
    end
    Wrapper.new(options)
  end

  def initialize(options = {}, &block)
    options = DEFAULTS.merge(options)

    @size = options.fetch(:size)
    @timeout = options.fetch(:timeout)
    @max_age = options.fetch(:max_age).to_f

    if @max_age <= 0
      raise ArgumentError.new(":max_age must be > 0")
    end

    if block_given?
      if options.include?(:connect_with)
        raise ArgumentError.new("Block passed to EzPool *and* :connect_with in options")
      else
        options[:connect_with] = block
      end
    end

    @manager = EzPool::ConnectionManager.new(options[:connect_with], options[:disconnect_with])

    @available = TimedStack.new(@manager, @size)
    @key = :"current-#{@available.object_id}"

    @checked_out_connections = Set.new
    @mutex = Mutex.new
  end

  def connect_with(&block)
    @manager.connect_with(&block)
  end

  def disconnect_with(&block)
    @manager.disconnect_with(&block)
  end

if Thread.respond_to?(:handle_interrupt)
  # MRI
  def with(options = {})
    Thread.handle_interrupt(Exception => :never) do
      conn = checkout(options)
      begin
        Thread.handle_interrupt(Exception => :immediate) do
          yield conn
        end
      ensure
        checkin conn
      end
    end
  end
else
  # non-MRI
  def with(options = {})
    conn = checkout(options)
    begin
      yield conn
    ensure
      checkin conn
    end
  end
end

  def checkout(options = {})
    conn_wrapper = nil
    while conn_wrapper.nil? do
      timeout = options[:timeout] || @timeout
      conn_wrapper = @available.pop(timeout: timeout)
      if expired? conn_wrapper
        @available.abandon(conn_wrapper)
        conn_wrapper = nil
      end
    end

    @mutex.synchronize do
      @checked_out_connections.add(conn_wrapper)
    end
    conn_wrapper
  end

  def checkin(conn_wrapper)
    known = @mutex.synchronize do
      @checked_out_connections.delete?(conn_wrapper)
    end
    if known.nil?
      raise EzPool::CheckedInUnCheckedOutConnectionError
    end
    if expired? conn_wrapper
      @available.abandon(conn_wrapper)
    else
      @available.push(conn_wrapper)
    end
    nil
  end

  def shutdown
    if block_given?
      raise ArgumentError.new("shutdown no longer accepts a block; call #disconnect_with to set the disconnect method, or pass the disconnect: option to the EzPool initializer")
    end
    @available.shutdown
  end

  private
  def expired?(connection_wrapper)
    return true if connection_wrapper.expired?

    if @max_age.finite?
      connection_wrapper.age > @max_age
    else
      false
    end
  end

  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown]

    def initialize(options = {}, &block)
      @pool = options.fetch(:pool) { ::EzPool.new(options, &block) }
    end

    def with(&block)
      @pool.with(&block)
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def respond_to?(id, *args)
      METHODS.include?(id) || with { |c| c.respond_to?(id, *args) }
    end

    def method_missing(name, *args, &block)
      with do |connection|
        connection.send(name, *args, &block)
      end
    end
  end
end
