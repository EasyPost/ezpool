# frozen_string_literal: true

require_relative 'monotonic_time'
require 'delegate'

class EzPool::ConnectionWrapper < SimpleDelegator
  attr_reader :raw_conn
  attr_reader :expired

  alias expired? expired

  def initialize(conn, connection_manager)
    @created_at = EzPool.monotonic_time
    @manager = connection_manager
    @expired = false
    @raw_conn = conn

    super(conn)
  end

  # Shut down the connection. Can no longer be used after this!
  def shutdown!
    @manager.disconnect(@raw_conn)
  end

  def expire!
    @expired = true
  end

  def age
    EzPool.monotonic_time - @created_at
  end
end
