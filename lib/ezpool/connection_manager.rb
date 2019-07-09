require_relative 'connection_wrapper'
require_relative 'errors'


class EzPool::ConnectionManager
  def initialize(connect_with, disconnect_with = nil, prove_with = nil)
    @connect_with = connect_with
    @disconnect_with = disconnect_with
    @prove_with = prove_with
  end

  def connect
    if @connect_with.nil?
      raise EzPool::ConnectCallableNeverConfigured.new()
    end
    @connect_with.call
  end

  def disconnect(conn)
    if !@disconnect_with.nil?
      @disconnect_with.call(conn)
    end
  end
  
  def prove(conn)
    if !@prove_with.nil?
      @prove_with.call(conn)
    end
  end

  def connect_with(&block)
    @connect_with = block
  end

  def disconnect_with(&block)
    @disconnect_with = block
  end
  
  def prove_with(&block)
    @prove_with = block
  end

  ##
  # Create a new wrapped connection
  def create_new
    EzPool::ConnectionWrapper.new(connect, self)
  end
end
