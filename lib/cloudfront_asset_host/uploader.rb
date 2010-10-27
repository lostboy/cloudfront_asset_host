require 'tempfile'

module CloudfrontAssetHost
  module Uploader

    class << self

      def upload!(options = {})
        puts "-- Updating uncompressed files" if options[:verbose]
        upload_keys_with_paths(keys_with_paths, options)

        if CloudfrontAssetHost.gzip
          puts "-- Updating compressed files" if options[:verbose]
          upload_keys_with_paths(gzip_keys_with_paths, options.merge(:gzip => true))
        end

        @existing_keys = nil
      end

      def upload_keys_with_paths(keys_paths, options={})
        gzip = options[:gzip] || false
        dryrun = options[:dryrun] || false
        verbose = options[:verbose] || false
        sigs = Hash.new
        keys_paths.each do |key, path|
          if should_upload?(key, options)
            puts "+ #{key}" if verbose

            extension = File.extname(path)[1..-1]
            
            #puts "path= #{path[(Rails.root.to_s.length+7)..-1]}"
            #puts "md5= #{CloudfrontAssetHost.key_for_path(path)}"
            sigs[path[(Rails.root.to_s.length+7)..-1]] = CloudfrontAssetHost.key_for_path(path)
            
            puts "mime for #{path[(Rails.root.to_s.length+7)..-1]} is #{ext_to_mime[extension]||'default'}"
            
            path = rewritten_css_path(path, sigs)

            data_path = gzip ? gzipped_path(path) : path
            
            s3.put_object(CloudfrontAssetHost.bucket, key, File.read(data_path), headers_for_path(extension, gzip).merge(:"x-amz-acl" => 'public-read')) unless dryrun

            File.unlink(data_path) if gzip && File.exists?(data_path)
          else
            puts "= #{key}" if verbose
          end
        end
        CloudfrontAssetHost.signatures = sigs
        File.open("#{Rails.root}/config/asset_signatures.yml", "w") do |f|
          f.write(sigs.to_yaml)
        end
      end

      def should_upload?(key, options={})
        return false if CloudfrontAssetHost.disable_cdn_for_source?(key)
        return true  if CloudfrontAssetHost.css?(key) && rewrite_all_css?

        options[:force_write] || !existing_keys.include?(key)
      end

      def gzipped_path(path)
        tmp = Tempfile.new("cfah-gz")
        `gzip '#{path}' -q -c > '#{tmp.path}'`
        tmp.path
      end

      def rewritten_css_path(path, sigs)
        if CloudfrontAssetHost.css?(path)
          tmp = CloudfrontAssetHost::CssRewriter.rewrite_stylesheet(path, sigs)
          tmp.path
        else
          path
        end
      end

      def keys_with_paths
        current_paths.inject({}) do |result, path|
          key = CloudfrontAssetHost.plain_prefix.present? ? "#{CloudfrontAssetHost.plain_prefix}/" : ""
          key << CloudfrontAssetHost.key_for_path(path) + path.gsub(Rails.public_path, '')

          result[key] = path
          result
        end
      end

      def gzip_keys_with_paths
        current_paths.inject({}) do |result, path|
          source = path.gsub(Rails.public_path, '')

          if CloudfrontAssetHost.gzip_allowed_for_source?(source)
            key = "#{CloudfrontAssetHost.gzip_prefix}/" << CloudfrontAssetHost.key_for_path(path) << source
            result[key] = path
          end

          result
        end
      end

      def rewrite_all_css?
        @rewrite_all_css ||= !keys_with_paths.delete_if { |key, path| existing_keys.include?(key) || !CloudfrontAssetHost.image?(path) }.empty?
      end

      def existing_keys
        @existing_keys ||= begin
          bucket_keys = s3.get_bucket(CloudfrontAssetHost.bucket).body["Contents"]
          bucket_keys.find_all do |key| 
            puts key["Key"]
            !key["Key"][/^app\//].nil?
            
          end          
        end
      end

      def current_paths
        @current_paths ||= Dir.glob("#{Rails.public_path}/{#{asset_dirs.join(',')}}/**/*").reject { |path| File.directory?(path) }
      end

      def headers_for_path(extension, gzip = false)
        mime = ext_to_mime[extension] || 'application/octet-stream'
        headers = {
          'Content-Type' => mime,
          'Cache-Control' => "max-age=#{10.years.to_i}",
          'Expires' => 1.year.from_now.utc.to_s
        }
        headers['Content-Encoding'] = 'gzip' if gzip

        headers
      end

      def ext_to_mime
        @ext_to_mime ||= Hash[ *( YAML::load_file(File.join(File.dirname(__FILE__), "mime_types.yml")).collect { |k,vv| vv.collect{ |v| [v,k] } }.flatten ) ]
      end

      def bucket
        @bucket ||= begin
          bucket = s3.bucket(CloudfrontAssetHost.bucket)
          bucket.disable_logging unless CloudfrontAssetHost.s3_logging
          bucket
        end
      end

      def s3
        #@s3 ||= RightAws::S3.new(config['access_key_id'], config['secret_access_key'])
        @s3 ||= Fog::AWS::Storage.new(:aws_access_key_id => config['access_key_id'], :aws_secret_access_key => config['secret_access_key'])
      end

      def config
        @config ||= begin 
          config = YAML::load_file(CloudfrontAssetHost.s3_config)
          config.has_key?(Rails.env) ? config[Rails.env] : config
        end
      end

      def asset_dirs
        @asset_dirs ||= CloudfrontAssetHost.asset_dirs
      end

    end

  end
end
