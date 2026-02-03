# Cache Coalescer

Distributed singleflight for Rails cache misses to prevent stampedes on cold keys.

## Install
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
- `ttl`: cache TTL in seconds
- `lock_ttl`: lock expiry (seconds)
- `wait_timeout`: how long waiters poll for a result
- `stale_ttl`: optional stale window; if set, stale values are returned on timeout
- `store`: any ActiveSupport cache store
- `lock_client`: Redis client or `Cache::Coalescer::Lock::InMemoryLock`

## Release
```bash
bundle exec rake release
```
