require_relative 'monotonic_time'

class EzPool::ConnectionWrapper
  attr_reader :raw_conn

  def initialize(conn, connection_manager)
    @raw_conn = conn
    @created_at = EzPool.monotonic_time
    @manager = connection_manager
  end

  # Shut down the connection. Can no longer be used after this!
  def shutdown!
    @manager.disconnect(@raw_conn)
  end
  
  def invalid?
    valid = @manager.prove(@raw_conn)
    
    res = true
    res = false unless (valid.nil? or !valid)
  end

  def age
    EzPool.monotonic_time - @created_at
  end
end
