require_relative 'connection_wrapper'


class ConnectionPool::ConnectionManager
  def initialize(connect_proc, disconnect_proc = nil)
    @connect_proc = connect_proc
    @disconnect_proc = disconnect_proc
  end

  def connect
    @connect_proc.call
  end

  def disconnect(conn)
    if !@disconnect_proc.nil?
      @disconnect_proc.call(conn)
    end
  end

  def connect_with(&block)
    @connect_proc = block
  end

  def disconnect_with(&block)
    @disconnect_proc = block
  end

  ##
  # Create a new wrapped connection
  def create_new
    ConnectionPool::ConnectionWrapper.new(connect, self)
  end
end
