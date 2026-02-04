# frozen_string_literal: true

require "active_support/notifications"
require "securerandom"
require "cache/coalescer/version"
require "cache/coalescer/lock"

module Cache
  module Coalescer
    class Error < StandardError; end

    class NullValue; end
    NULL_VALUE = NullValue.new

    DEFAULT_LOCK_TTL = 5
    DEFAULT_WAIT_TIMEOUT = 5
    DEFAULT_WAIT_SLEEP = 0.05

    def self.fetch(key, ttl:, store: nil, lock_ttl: DEFAULT_LOCK_TTL, wait_timeout: DEFAULT_WAIT_TIMEOUT,
                   wait_sleep: DEFAULT_WAIT_SLEEP, stale_ttl: nil, lock_client: nil, cache_nil: false, &block)
      raise ArgumentError, "block required" unless block

      store ||= default_store
      value = store.read(key)
      return nil if null_value?(value)
      return value unless value.nil?

      lock_client ||= store.respond_to?(:redis) ? Lock.default_for(store) : Lock::InMemoryLock.new
      lock_key = lock_key_for(key)
      token = SecureRandom.uuid

      if lock_client.acquire(lock_key, token, lock_ttl)
        return compute_and_store(store, key, ttl, stale_ttl, lock_client, lock_key, token, cache_nil, &block)
      end

      deadline = monotonic + wait_timeout
      loop do
        value = store.read(key)
        return nil if null_value?(value)
        return value unless value.nil?
        break if monotonic >= deadline
        sleep wait_sleep
      end

      if lock_client.acquire(lock_key, token, lock_ttl)
        return compute_and_store(store, key, ttl, stale_ttl, lock_client, lock_key, token, cache_nil, &block)
      end

      if stale_ttl
        stale_value = store.read(stale_key_for(key))
        return nil if null_value?(stale_value)
        return stale_value unless stale_value.nil?
      end

      nil
    end

    def self.default_store
      return Rails.cache if defined?(Rails) && Rails.respond_to?(:cache)
      raise Error, "store is required when Rails.cache is unavailable"
    end

    def self.compute_and_store(store, key, ttl, stale_ttl, lock_client, lock_key, token, cache_nil)
      value = yield
      stored_value = cache_nil && value.nil? ? NULL_VALUE : value
      store.write(key, stored_value, expires_in: ttl)
      if stale_ttl
        store.write(stale_key_for(key), stored_value, expires_in: ttl + stale_ttl)
      end
      value
    ensure
      lock_client.release(lock_key, token) if lock_client
    end

    def self.lock_key_for(key)
      "cache-coalescer:lock:#{key}"
    end

    def self.stale_key_for(key)
      "cache-coalescer:stale:#{key}"
    end

    def self.monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.null_value?(value)
      value.is_a?(NullValue)
    end
  end
end

require "cache/coalescer/railtie"
