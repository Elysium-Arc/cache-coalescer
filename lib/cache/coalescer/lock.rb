# frozen_string_literal: true

module Cache
  module Coalescer
    module Lock
      LUA_RELEASE = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      def self.default_for(store)
        return RedisLock.new(store.redis) if store.respond_to?(:redis)
        raise Cache::Coalescer::Error, "lock_client is required when store does not expose redis"
      end

      class RedisLock
        def initialize(redis)
          @redis = redis
        end

        def acquire(key, token, ttl)
          with_redis do |conn|
            conn.set(key, token, nx: true, px: (ttl * 1000).to_i)
          end
        end

        def release(key, token)
          with_redis do |conn|
            conn.eval(LUA_RELEASE, keys: [key], argv: [token])
          end
        rescue StandardError
          false
        end

        private

        def with_redis
          if @redis.respond_to?(:with)
            @redis.with { |conn| yield conn }
          else
            yield @redis
          end
        end
      end

      class InMemoryLock
        def initialize
          @mutex = Mutex.new
          @locks = {}
        end

        def acquire(key, _token, ttl)
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @mutex.synchronize do
            expires_at = @locks[key]
            return false if expires_at && expires_at > now
            @locks[key] = now + ttl
            true
          end
        end

        def release(key, _token)
          @mutex.synchronize { @locks.delete(key) }
          true
        end
      end
    end
  end
end
