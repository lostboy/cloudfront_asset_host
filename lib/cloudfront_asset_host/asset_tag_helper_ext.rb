module ActionView
  module Helpers
    module AssetTagHelper

    private

      # Override asset_id so it calculates the key by md5 instead of modified-time
      def rails_asset_id_with_cloudfront(source, s)
        #puts "[rails_asset_id_with_cloudfront] #{source}"
        #if @@cache_asset_timestamps && (asset_id = @@asset_timestamps_cache[source])
        #  asset_id
        #else
          
          #path = File.join(Rails.public_path, source)
          rewrite_path = !CloudfrontAssetHost.disable_cdn_for_source?(source)
          #asset_id = rewrite_path ? CloudfrontAssetHost.key_for_path(path) : ''
          #asset_id = rewrite_path ? YAML::load(File.new("#{Rails.root}/config/asset_signatures.yml"))[source] : ''
          asset_id = rewrite_path ? CloudfrontAssetHost.signatures[source] : ''
          
          #if @@cache_asset_timestamps
          #  @@asset_timestamps_cache_guard.synchronize do
          #    @@asset_timestamps_cache[source] = asset_id
          #  end
          #end

          asset_id
        #end
      end

      # Override asset_path so it prepends the asset_id
      def rewrite_asset_path_with_cloudfront(source, s)
        #puts "[rewrite_asset_path_with_cloudfront] #{source}"
        asset_id = rails_asset_id(source, s)
        if asset_id.blank?
          source
        else
          "/#{asset_id}#{source}"
        end
      end

    end
  end
end
