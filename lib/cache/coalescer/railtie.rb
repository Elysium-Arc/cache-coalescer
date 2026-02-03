# frozen_string_literal: true

# :nocov:
begin
  require "rails/railtie"
rescue LoadError
end

if defined?(Rails::Railtie)
  module Cache
    module Coalescer
      module StoreExtension
        def fetch_coalesced(key, ttl:, **options, &block)
          Cache::Coalescer.fetch(key, ttl: ttl, store: self, **options, &block)
        end
      end

      class Railtie < Rails::Railtie
        initializer "cache_coalescer.extend_cache" do
          require "active_support/cache"
          ::ActiveSupport::Cache::Store.include(Cache::Coalescer::StoreExtension)
        end
      end
    end
  end
end
# :nocov:
