# Cache Coalescer

[![Gem Version](https://img.shields.io/gem/v/cache-coalescer.svg)](https://rubygems.org/gems/cache-coalescer)
[![Gem Downloads](https://img.shields.io/gem/dt/cache-coalescer.svg)](https://rubygems.org/gems/cache-coalescer)
[![Ruby](https://img.shields.io/badge/ruby-3.0%2B-cc0000.svg)](https://www.ruby-lang.org)
[![CI](https://github.com/Elysium-Arc/cache-coalescer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Elysium-Arc/cache-coalescer/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Elysium-Arc/cache-coalescer.svg)](https://github.com/Elysium-Arc/cache-coalescer/releases)
[![Rails](https://img.shields.io/badge/rails-6.x%20%7C%207.x%20%7C%208.x-cc0000.svg)](https://rubyonrails.org)
[![Elysium Arc](https://img.shields.io/badge/Elysium%20Arc-Reliability%20Toolkit-0b3d91.svg)](https://github.com/Elysium-Arc)

Distributed singleflight for Rails cache misses to prevent stampedes on cold keys.

## About
Cache Coalescer ensures only one request computes a missing value while the rest wait for it. The first caller acquires a lock, computes, and writes to cache. Other callers poll briefly and reuse the result. Optional stale values can be served if the lock is held for too long.

This is ideal for expensive cache-miss work such as API calls, report generation, or heavyweight database queries.

## Use Cases
- Prevent thundering herds on cold cache keys
- Reduce p99 latency spikes during traffic bursts
- Protect downstream services from request stampedes
- Coalesce expensive fan-out workloads into a single computation

## Compatibility
- Ruby 3.0+
- ActiveSupport 6.1+
- Works with any ActiveSupport cache store
- Best with Redis-backed stores for distributed locking

## Elysium Arc Reliability Toolkit
Also check out these related gems:
- Cache SWR: https://github.com/Elysium-Arc/cache-swr
- Faraday Hedge: https://github.com/Elysium-Arc/faraday-hedge
- Rack Idempotency Kit: https://github.com/Elysium-Arc/rack-idempotency-kit
- Env Contract: https://github.com/Elysium-Arc/env-contract

## Installation
```ruby
# Gemfile

gem "cache-coalescer"
```

## Usage
```ruby
value = Cache::Coalescer.fetch("expensive-key", ttl: 60, lock_ttl: 5, wait_timeout: 2, store: Rails.cache) do
  ExpensiveQuery.call
end
```

Rails integration adds `Rails.cache.fetch_coalesced`:
```ruby
Rails.cache.fetch_coalesced("expensive-key", ttl: 60) { ExpensiveQuery.call }
```

## Options
- `ttl` (Integer) cache TTL in seconds
- `lock_ttl` (Integer) lock expiry in seconds
- `wait_timeout` (Float) how long waiters poll for a result
- `wait_sleep` (Float) polling interval in seconds
- `stale_ttl` (Integer) optional stale window; if set, stale values are returned on timeout
- `cache_nil` (Boolean) store nil values to avoid re-computation
- `store` ActiveSupport cache store (defaults to `Rails.cache` when available)
- `lock_client` Redis client or `Cache::Coalescer::Lock::InMemoryLock`

## Locking
If the cache store exposes `redis`, a Redis lock is used automatically. Otherwise, the gem falls back to an in-memory lock which is safe for single-process usage.

## Release
```bash
bundle exec rake release
```
