# frozen_string_literal: true

require "rails/railtie"

module Cache
  module Coalescer
    module StoreExtension
      def fetch_coalesced(key, ttl:, **options, &block)
        Cache::Coalescer.fetch(key, ttl: ttl, store: self, **options, &block)
      end
    end

    class Railtie < Rails::Railtie
      initializer "cache_coalescer.extend_cache" do
        ActiveSupport.on_load(:active_support_cache) do
          ::ActiveSupport::Cache::Store.include(Cache::Coalescer::StoreExtension)
        end
      end
    end
  end
end
