# frozen_string_literal: true

require_relative 'helper'

class TestEzPool < Minitest::Test

  class NetworkConnection
    SLEEP_TIME = 0.1

    def initialize
      @x = 0
    end

    def do_something
      @x += 1
      sleep SLEEP_TIME
      @x
    end

    def fast
      @x += 1
    end

    def do_something_with_block
      @x += yield
      sleep SLEEP_TIME
      @x
    end

    def respond_to?(method_id, *args)
      method_id == :do_magic || super(method_id, *args)
    end
  end

  class Recorder
    def initialize
      @calls = []
    end

    attr_reader :calls

    def do_work(label)
      @calls << label
    end
  end

  def use_pool(pool, size)
    Array.new(size) do
      Thread.new do
        pool.with do sleep end
      end
    end.each do |thread|
      Thread.pass until thread.status == 'sleep'
    end
  end

  def kill_threads(threads)
    threads.each do |thread|
      thread.kill
      thread.join
    end
  end

  def test_basic_multithreaded_usage
    pool_size = 5
    pool = EzPool.new(size: pool_size) { NetworkConnection.new }

    start = Time.new

    generations = 3

    result = Array.new(pool_size * generations) do
      Thread.new do
        pool.with do |net|
          net.do_something
        end
      end
    end.map(&:value)

    finish = Time.new

    assert_equal((1..generations).cycle(pool_size).sort, result.sort)

    assert_operator(finish - start, :>, generations * NetworkConnection::SLEEP_TIME)
  end

  def test_timeout
    pool = EzPool.new(timeout: 0, size: 1) { NetworkConnection.new }
    thread = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while thread.status == 'run'

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    thread.join

    pool.with do |conn|
      refute_nil conn
    end
  end

  def test_with
    pool = EzPool.new(
      timeout: 0,
      size: 1,
      connect_with: lambda { Object.new }
    )

    pool.with do
      assert_raises Timeout::Error do
        Thread.new { pool.checkout }.join
      end
    end

    assert Thread.new { pool.checkout }.join
  end

  def test_with_timeout
    pool = EzPool.new(
      timeout: 0,
      size: 1,
      connect_with: lambda { Object.new }
    )

    assert_raises Timeout::Error do
      Timeout.timeout(0.01) do
        pool.with do |obj|
          assert_equal 0, pool.instance_variable_get(:@available).instance_variable_get(:@que).size
          sleep 0.015
        end
      end
    end
    assert_equal 1, pool.instance_variable_get(:@available).instance_variable_get(:@que).size
  end

  def test_checkout_ignores_timeout
    skip("Thread.handle_interrupt not available") unless Thread.respond_to?(:handle_interrupt)

    pool = EzPool.new(
      timeout: 0,
      size: 1,
      connect_with: lambda { Object.new }
    )

    def pool.checkout(options)
      sleep 0.015
      super
    end

    did_something = false
    assert_raises Timeout::Error do
      Timeout.timeout(0.01) do
        pool.with do |obj|
          did_something = true
          # Timeout::Error will be triggered by any non-trivial Ruby code
          # executed here since it couldn't be raised during checkout.
          # It looks like setting the local variable above does not trigger
          # the Timeout check in MRI 2.2.1.
          obj.tap { obj.hash }
        end
      end
    end
    assert did_something
    assert_equal 1, pool.instance_variable_get(:@available).instance_variable_get(:@que).size
  end

  def test_explicit_return
    pool = EzPool.new(timeout: 0, size: 1)
    pool.connect_with do
      mock = Minitest::Mock.new
      def mock.disconnect!
        raise "should not disconnect upon explicit return"
      end
      mock
    end

    pool.with do |conn|
      return true
    end
  end

  def test_with_timeout_override
    pool = EzPool.new(timeout: 0, size: 1) { NetworkConnection.new }

    t = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while t.status == 'run'

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    pool.with(timeout: 2 * NetworkConnection::SLEEP_TIME) do |conn|
      refute_nil conn
    end
  end

  def test_checkin
    pool = EzPool.new(timeout: 0, size: 1) { NetworkConnection.new }
    conn = pool.checkout

    assert_raises Timeout::Error do
      Thread.new { pool.checkout }.join
    end

    pool.checkin conn

    assert_same conn, Thread.new { pool.checkout }.value
  end

  def test_returns_value
    pool = EzPool.new(timeout: 0, size: 1) { Object.new }
    assert_equal 1, pool.with { |_o| 1 }
  end

  def test_checkin_garbage
    pool = EzPool.new(timeout: 0, size: 1) { Object.new }

    assert_raises EzPool::CheckedInUnCheckedOutConnectionError do
      pool.checkin nil
    end
  end

  def test_checkout
    pool = EzPool.new(size: 2) { NetworkConnection.new }

    conn = pool.checkout

    assert_kind_of EzPool::ConnectionWrapper, conn
    assert_kind_of NetworkConnection, conn.raw_conn

    refute_same conn, pool.checkout
  end

  def test_checkout_multithread
    pool = EzPool.new(size: 2) { NetworkConnection.new }
    conn = pool.checkout

    t = Thread.new do
      pool.checkout
    end

    refute_same conn, t.value
  end

  def test_checkout_timeout
    pool = EzPool.new(timeout: 0, size: 0) { Object.new }

    assert_raises Timeout::Error do
      pool.checkout
    end
  end

  def test_checkout_timeout_override
    pool = EzPool.new(timeout: 0, size: 1) { NetworkConnection.new }

    thread = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while thread.status == 'run'

    assert_raises Timeout::Error do
      pool.checkout
    end

    assert pool.checkout timeout: 2 * NetworkConnection::SLEEP_TIME
  end

  def test_passthru
    pool = EzPool.wrap(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    assert_equal 1, pool.do_something
    assert_equal 2, pool.do_something
    assert_equal 5, pool.do_something_with_block { 3 }
    assert_equal 6, pool.with { |net| net.fast }
  end

  def test_passthru_respond_to
    pool = EzPool.wrap(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    assert pool.respond_to?(:with)
    assert pool.respond_to?(:do_something)
    assert pool.respond_to?(:do_magic)
    refute pool.respond_to?(:do_lots_of_magic)
  end

  def test_return_value
    pool = EzPool.new(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    result = pool.with do |net|
      net.fast
    end
    assert_equal 1, result
  end

  def test_heavy_threading
    pool = EzPool.new(timeout: 0.5, size: 3) { NetworkConnection.new }

    threads = Array.new(20) do
      Thread.new do
        pool.with do |net|
          sleep 0.01
        end
      end
    end

    threads.map { |thread| thread.join }
  end

  def test_reuses_objects_when_pool_not_saturated
    pool = EzPool.new(size: 5) { NetworkConnection.new }

    ids = 10.times.map do
      pool.with { |c| c.object_id }
    end

    assert_equal 1, ids.uniq.size
  end

  def test_nested_checkout_fails
    recorder = Recorder.new
    pool = EzPool.new(size: 1) { recorder }
    pool.with do |r_outer|
      @other = Thread.new do |t|
        pool.with do |r_other|
          r_other.do_work('other')
        end
      end

      Thread.pass

      r_outer.do_work('outer')
    end

    @other.join

    assert_equal ['outer', 'other'], recorder.calls
  end

  def test_shutdown_is_executed_for_all_connections
    recorders = []

    pool = EzPool.new(size: 3) do
      Recorder.new.tap { |r| recorders << r }
    end

    threads = use_pool pool, 3

    pool.disconnect_with do |recorder|
      recorder.do_work("shutdown")
    end

    pool.shutdown

    kill_threads(threads)

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_shutdown_works_as_argument_to_ezpool
    recorders = []
    pool = EzPool.new(
      size: 3,
      connect_with: lambda { Recorder.new.tap { |r| recorders << r } },
      disconnect_with: lambda { |recorder| recorder.do_work("shutdown")}
    )

    threads = use_pool pool, 3

    pool.shutdown

    kill_threads(threads)

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_raises_error_after_shutting_down
    pool = EzPool.new(size: 1) { true }

    pool.shutdown

    assert_raises EzPool::PoolShuttingDownError do
      pool.checkout
    end
  end

  def test_runs_shutdown_block_asynchronously_if_connection_was_in_use
    recorders = []

    pool = EzPool.new(
      size: 3,
      connect_with: lambda { Recorder.new.tap { |r| recorders << r } },
      disconnect_with: lambda { |recorder| recorder.do_work("shutdown") }
    )

    threads = use_pool pool, 2

    conn = pool.checkout

    pool.shutdown

    kill_threads(threads)

    assert_equal [["shutdown"], ["shutdown"], []], recorders.map { |r| r.calls }

    pool.checkin conn

    assert_equal [["shutdown"], ["shutdown"], ["shutdown"]], recorders.map { |r| r.calls }
  end

  def test_max_age
    recorders = []

    pool = EzPool.new(
      size: 3, max_age: 0.1,
      connect_with: lambda { Recorder.new.tap { |r| recorders << r } },
      disconnect_with: lambda { |conn| conn.do_work("shutdown") }
    )

    pool.with do |conn|
      sleep(0.2)
    end

    pool.with do |conn|
      sleep(0.2)
    end

    assert_equal [["shutdown"], ["shutdown"]], recorders.map { |r| r.calls }
  end

  def test_connect_with
    conn_cls = Struct.new("Conn")

    pool = EzPool.new(size: 1, connect_with: proc { conn_cls.new })
    
    pool.with do |conn|
      assert_instance_of(EzPool::ConnectionWrapper, conn)
      assert_instance_of(conn_cls, conn.raw_conn)
    end
  end

  def test_shutdown_is_executed_for_all_connections_in_wrapped_pool
    recorders = []

    wrapper = EzPool::Wrapper.new(
      size: 3,
      connect_with: lambda { Recorder.new.tap { |r| recorders << r } },
      disconnect_with: lambda { |recorder| recorder.do_work("shutdown") }
    )

    threads = use_pool wrapper, 3

    wrapper.pool_shutdown

    kill_threads(threads)

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_wrapper_method_missing
    wrapper = EzPool::Wrapper.new { NetworkConnection.new }
    assert_equal 1, wrapper.fast
  end

  def test_wrapper_respond_to_eh
    wrapper = EzPool::Wrapper.new { NetworkConnection.new }

    assert_respond_to wrapper, :with

    assert_respond_to wrapper, :fast
    refute_respond_to wrapper, :"nonexistent method"
  end

  def test_wrapper_with
    wrapper = EzPool::Wrapper.new(timeout: 0, size: 1) { Object.new }

    wrapper.with do
      assert_raises Timeout::Error do
        Thread.new do
          wrapper.with { flunk 'connection checked out :(' }
        end.join
      end
    end

    assert Thread.new { wrapper.with { } }.join
  end

  class ConnWithEval
    def eval(arg)
      "eval'ed #{arg}"
    end
  end

  def test_wrapper_kernel_methods
    wrapper = EzPool::Wrapper.new(timeout: 0, size: 1) { ConnWithEval.new }

    assert_equal "eval'ed 1", wrapper.eval(1)
  end

  def test_wrapper_with_ezpool
    recorder = Recorder.new
    pool = EzPool.new(size: 1) { recorder }
    wrapper = EzPool::Wrapper.new(pool: pool)

    pool.with { |r| r.do_work('with') }
    wrapper.do_work('wrapped')

    assert_equal %w[with wrapped], recorder.calls
  end

  def test_ezpool_wrapper_manual_expiration
    recorder = Recorder.new
    pool = TestPool.new(size: 1) { recorder }

    pool.with do |r|
      r.do_work(r.object_id)
      r.expire!
    end

    pool.with { |r| r.do_work(r.object_id) }

    refute_equal(*recorder.calls)
  end
end
