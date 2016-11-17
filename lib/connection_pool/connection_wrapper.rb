require_relative 'monotonic_time'

class ConnectionPool::ConnectionWrapper
  attr_reader :raw_conn

  def initialize(conn, connection_manager)
    @raw_conn = conn
    @created_at = ConnectionPool.monotonic_time
    @manager = connection_manager
  end

  # Shut down the connection. Can no longer be used after this!
  def shutdown!
    @manager.disconnect(@raw_conn)
  end

  def age
    ConnectionPool.monotonic_time - @created_at
  end
end
