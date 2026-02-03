# frozen_string_literal: true

require "active_support/cache"

class CoalescerSpecRedis
  def initialize
    @data = {}
  end

  def set(key, token, nx:, px:)
    return false if nx && @data.key?(key)
    @data[key] = token
    true
  end

  def eval(_script, keys:, argv:)
    if @data[keys[0]] == argv[0]
      @data.delete(keys[0])
      1
    else
      0
    end
  end
end

class CoalescerSpecStore
  def initialize(redis)
    @redis = redis
    @data = {}
  end

  def read(key)
    @data[key]
  end

  def write(key, value, expires_in: nil)
    @data[key] = value
    true
  end

  def redis
    @redis
  end
end

RSpec.describe Cache::Coalescer do
  it "raises when no store is available" do
    expect { described_class.default_store }.to raise_error(Cache::Coalescer::Error)
  end

  it "uses Rails.cache when available" do
    store = ActiveSupport::Cache::MemoryStore.new
    stub_const("Rails", Module.new)
    Rails.define_singleton_method(:cache) { store }

    expect(described_class.default_store).to eq(store)
  end

  it "raises when no block is provided" do
    store = ActiveSupport::Cache::MemoryStore.new
    expect { described_class.fetch("key", ttl: 1, store: store) }.to raise_error(ArgumentError)
  end

  it "returns cached value without locking" do
    store = ActiveSupport::Cache::MemoryStore.new
    store.write("key", "value")

    result = described_class.fetch("key", ttl: 1, store: store) { "new" }

    expect(result).to eq("value")
  end

  it "uses default store in fetch when store is nil" do
    store = ActiveSupport::Cache::MemoryStore.new
    stub_const("Rails", Module.new)
    Rails.define_singleton_method(:cache) { store }

    value = described_class.fetch("key", ttl: 1) { "value" }
    expect(value).to eq("value")
  end

  it "coalesces concurrent cache misses" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Cache::Coalescer::Lock::InMemoryLock.new
    counter = 0

    threads = 5.times.map do
      Thread.new do
        described_class.fetch("key", ttl: 1, store: store, lock_client: lock) do
          sleep 0.05
          counter += 1
          "value"
        end
      end
    end

    results = threads.map(&:value)
    expect(counter).to eq(1)
    expect(results).to all(eq("value"))
  end

  it "retries lock acquisition after waiting" do
    store = ActiveSupport::Cache::MemoryStore.new
    calls = 0
    lock = Class.new do
      def initialize(calls)
        @calls = calls
      end

      def acquire(_key, _token, _ttl)
        @calls[0] += 1
        @calls[0] > 1
      end

      def release(*_args); end
    end
    calls_box = [0]
    lock_client = lock.new(calls_box)

    result = described_class.fetch("key", ttl: 1, store: store, lock_client: lock_client, wait_timeout: 0.01) { "value" }

    expect(result).to eq("value")
    expect(calls_box[0]).to be >= 2
  end

  it "returns value when it appears while waiting" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Class.new do
      def acquire(*_args) = false
      def release(*_args); end
    end.new

    Thread.new do
      sleep 0.02
      store.write("key", "value")
    end

    result = described_class.fetch("key", ttl: 1, store: store, lock_client: lock, wait_timeout: 0.1) { "new" }
    expect(result).to eq("value")
  end

  it "returns stale value when lock is held and stale_ttl is set" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Cache::Coalescer::Lock::InMemoryLock.new
    lock.acquire("cache-coalescer:lock:key", "token", 1)
    store.write("cache-coalescer:stale:key", "stale")

    fresh_block = proc { "fresh" }
    fresh_block.call
    value = described_class.fetch("key", ttl: 1, store: store, lock_client: lock, wait_timeout: 0.01, stale_ttl: 60, &fresh_block)

    expect(value).to eq("stale")
  end

  it "returns nil when stale_ttl is set but no stale value exists" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Cache::Coalescer::Lock::InMemoryLock.new
    lock.acquire("cache-coalescer:lock:key", "token", 1)

    value_block = proc { "value" }
    value_block.call
    value = described_class.fetch("key", ttl: 1, store: store, lock_client: lock, wait_timeout: 0.01, stale_ttl: 60, &value_block)

    expect(value).to be_nil
  end

  it "returns nil when lock is held and no stale value exists" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Cache::Coalescer::Lock::InMemoryLock.new
    lock.acquire("cache-coalescer:lock:key", "token", 1)

    value_block = proc { "value" }
    value_block.call
    value = described_class.fetch("key", ttl: 1, store: store, lock_client: lock, wait_timeout: 0.01, &value_block)

    expect(value).to be_nil
  end

  it "writes stale value when stale_ttl is provided" do
    store = ActiveSupport::Cache::MemoryStore.new
    lock = Cache::Coalescer::Lock::InMemoryLock.new

    described_class.fetch("key", ttl: 1, store: store, lock_client: lock, stale_ttl: 10) { "value" }

    expect(store.read("cache-coalescer:stale:key")).to eq("value")
  end

  it "skips lock release when lock_client is nil" do
    store = ActiveSupport::Cache::MemoryStore.new

    value = described_class.compute_and_store(store, "key", 1, nil, nil, "lock", "token") { "value" }

    expect(value).to eq("value")
    expect(store.read("key")).to eq("value")
  end

  it "uses default redis lock when store exposes redis" do
    redis = CoalescerSpecRedis.new
    store = CoalescerSpecStore.new(redis)

    value = described_class.fetch("key", ttl: 1, store: store) { "value" }
    expect(value).to eq("value")
  end
end

RSpec.describe Cache::Coalescer::Lock do
  class RedisWith
    def initialize(redis)
      @redis = redis
    end

    def with
      yield @redis
    end
  end

  class ErrorRedis
    def eval(*_args)
      raise "boom"
    end

    def set(*_args)
      true
    end
  end

  it "builds a redis lock for stores exposing redis" do
    store = Struct.new(:redis).new(CoalescerSpecRedis.new)
    lock = described_class.default_for(store)
    expect(lock).to be_a(Cache::Coalescer::Lock::RedisLock)
  end

  it "raises when store does not expose redis" do
    expect { described_class.default_for(Object.new) }.to raise_error(Cache::Coalescer::Error)
  end

  it "acquires and releases redis locks" do
    redis = CoalescerSpecRedis.new
    lock = Cache::Coalescer::Lock::RedisLock.new(redis)

    expect(lock.acquire("key", "token", 1)).to eq(true)
    expect(lock.acquire("key", "token", 1)).to eq(false)
    expect(lock.release("key", "token")).to eq(1)
  end

  it "returns 0 when release token does not match" do
    redis = CoalescerSpecRedis.new
    lock = Cache::Coalescer::Lock::RedisLock.new(redis)

    lock.acquire("key", "token", 1)
    expect(lock.release("key", "other")).to eq(0)
  end

  it "uses #with when available" do
    redis = CoalescerSpecRedis.new
    lock = Cache::Coalescer::Lock::RedisLock.new(RedisWith.new(redis))

    expect(lock.acquire("key", "token", 1)).to eq(true)
  end

  it "returns false when release fails" do
    lock = Cache::Coalescer::Lock::RedisLock.new(ErrorRedis.new)
    expect(lock.release("key", "token")).to eq(false)
  end

  it "acquires when redis responds to set" do
    lock = Cache::Coalescer::Lock::RedisLock.new(ErrorRedis.new)
    expect(lock.acquire("key", "token", 1)).to eq(true)
  end

  it "in-memory lock respects ttl" do
    lock = Cache::Coalescer::Lock::InMemoryLock.new
    expect(lock.acquire("key", "token", 0.1)).to eq(true)
    expect(lock.acquire("key", "token", 0.1)).to eq(false)
  end
end
