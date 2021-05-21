require_relative 'monotonic_time'

class EzPool::ConnectionWrapper
  attr_reader :raw_conn

  def initialize(conn, connection_manager)
    @raw_conn = conn
    @created_at = EzPool.monotonic_time
    @used_at = @created_at
    @manager = connection_manager
  end

  # Shut down the connection. Can no longer be used after this!
  def shutdown!
    @manager.disconnect(@raw_conn)
  end

  def age
    EzPool.monotonic_time - @created_at
  end

  def idle_time
    EzPool.monotonic_time - @used_at
  end

  def touch_connection
    @used_at = EzPool.monotonic_time
  end
end
