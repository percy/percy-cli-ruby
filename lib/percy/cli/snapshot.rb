require 'find'
require 'digest'
require 'uri'
require 'thread/pool'
require 'percy/cli/client'

Thread.abort_on_exception = true
Thread::Pool.abort_on_exception = true

module Percy
  class Cli
    module Snapshot
      # Static resource types that an HTML file might load and that we want to upload for rendering.
      STATIC_RESOURCE_EXTENSIONS = [
        '.css', '.js', '.jpg', '.jpeg', '.gif', '.ico', '.png', '.bmp', '.pict', '.tif', '.tiff',
        '.ttf', '.eot', '.woff', '.otf', '.svg', '.svgz', '.webp', '.ps',
      ].freeze

      DEFAULT_SNAPSHOTS_REGEX = /\.(html|htm)$/
      MAX_FILESIZE_BYTES = 15 * 1024**2 # 15 MB.

      def run_snapshot(root_dir, options = {})
        repo = options[:repo] || Percy.config.repo
        root_dir = File.expand_path(File.absolute_path(root_dir))
        strip_prefix = File.expand_path(File.absolute_path(options[:strip_prefix] || root_dir))
        num_threads = options[:threads] || 10
        snapshot_limit = options[:snapshot_limit]
        baseurl = options[:baseurl] || '/'
        enable_javascript = !!options[:enable_javascript]
        include_all = !!options[:include_all]
        widths = options[:widths].map { |w| Integer(w) }
        raise ArgumentError, 'baseurl must start with /' if baseurl[0] != '/'

        base_resource_options = {strip_prefix: strip_prefix, baseurl: baseurl}

        Percy::Cli::Client.new

        # Find all the static files in the given root directory.
        root_paths = find_root_paths(root_dir, snapshots_regex: options[:snapshots_regex])
        resource_paths = find_resource_paths(root_dir, include_all: include_all)
        root_resources = list_resources(root_paths, base_resource_options.merge(is_root: true))
        build_resources = list_resources(resource_paths, base_resource_options)
        all_resources = root_resources + build_resources

        if root_resources.empty?
          say 'No root resource files found. Are there HTML files in the given directory?'
          exit(-1)
        end

        build_resources.each do |resource|
          Percy.logger.debug { "Found build resource: #{resource.resource_url}" }
        end

        build = rescue_connection_failures do
          say 'Creating build...'

          build = Percy.create_build(repo, resources: build_resources)

          say 'Uploading build resources...'
          upload_missing_resources(build, build, all_resources, num_threads: num_threads)

          build
        end
        return if failed?

        # Upload a snapshot for every root resource, and associate the build_resources.
        output_lock = Mutex.new
        snapshot_thread_pool = Thread.pool(num_threads)
        total = snapshot_limit ? [root_resources.length, snapshot_limit].min : root_resources.length

        root_resources.each_with_index do |root_resource, i|
          break if snapshot_limit && i + 1 > snapshot_limit

          snapshot_thread_pool.process do
            output_lock.synchronize do
              say "Uploading snapshot (#{i + 1}/#{total}): #{root_resource.resource_url}"
            end

            rescue_connection_failures do
              snapshot = Percy.create_snapshot(
                build['data']['id'],
                [root_resource],
                enable_javascript: enable_javascript,
                widths: widths,
              )
              upload_missing_resources(build, snapshot, all_resources, num_threads: num_threads)
              Percy.finalize_snapshot(snapshot['data']['id'])
            end
          end
        end

        snapshot_thread_pool.wait
        snapshot_thread_pool.shutdown

        # Finalize the build.
        say 'Finalizing build...'
        rescue_connection_failures { Percy.finalize_build(build['data']['id']) }

        return if failed?

        say 'Done! Percy is now processing, you can view the visual diffs here:'
        say build['data']['attributes']['web-url']
      end

      private

      def failed?
        !!@failed
      end

      def rescue_connection_failures
        raise ArgumentError, 'block is requried' unless block_given?
        begin
          yield
        rescue Percy::Client::ServerError, # Rescue server errors.
               Percy::Client::UnauthorizedError, # Rescue unauthorized errors (no auth creds setup).
               Percy::Client::PaymentRequiredError, # Rescue quota exceeded errors.
               Percy::Client::ConflictError, # Rescue project disabled errors and others.
               Percy::Client::ConnectionFailed, # Rescue some networking errors.
               Percy::Client::TimeoutError => e

          Percy.logger.error(e)
          @failed = true
          nil
        end
      end

      def find_root_paths(dir_path, options = {})
        find_files(dir_path).select { |path| include_root_path?(path, options) }
      end

      def find_resource_paths(dir_path, options = {})
        find_files(dir_path).select { |path| include_resource_path?(path, options) }
      end

      def maybe_add_protocol(url)
        url[0..1] == '//' ? "http:#{url}" : url
      end

      def list_resources(paths, options = {})
        strip_prefix = File.expand_path(options[:strip_prefix])
        baseurl = options[:baseurl]
        resources = []

        # Strip trailing slash from strip_prefix.
        strip_prefix = strip_prefix[0..-2] if strip_prefix[-1] == '/'

        paths.each do |path|
          sha = Digest::SHA256.hexdigest(File.read(path))
          next if File.size(path) > MAX_FILESIZE_BYTES
          resource_url = URI.escape(File.join(baseurl, path.sub(strip_prefix, '')))

          resources << Percy::Client::Resource.new(
            resource_url, sha: sha, is_root: options[:is_root], path: path,
          )
        end
        resources
      end

      # Uploads missing resources either for a build or snapshot.
      def upload_missing_resources(build, obj, potential_resources, options = {})
        # Upload the content for any missing resources.
        missing_resources = obj['data']['relationships']['missing-resources']['data']

        bar = Commander::UI::ProgressBar.new(
          missing_resources.length,
          title: 'Uploading resources...',
          format: ':title |:progress_bar| :percent_complete% complete - :resource_url',
          width: 20,
          complete_message: nil,
        )

        output_lock = Mutex.new
        uploader_thread_pool = Thread.pool(options[:num_threads] || 10)

        missing_resources.each do |missing_resource|
          uploader_thread_pool.process do
            missing_resource_sha = missing_resource['id']
            resource = potential_resources.find { |r| r.sha == missing_resource_sha }

            output_lock.synchronize do
              bar.increment resource_url: resource.resource_url
            end

            # Remote resources are stored in 'content', local resources are
            # read from the filesystem.
            content = resource.content || File.read(resource.path.to_s)

            Percy.upload_resource(build['data']['id'], content)
          end
        end

        uploader_thread_pool.wait
        uploader_thread_pool.shutdown
      end

      # A file find method that follows directory and file symlinks.
      def find_files(*paths)
        paths.flatten!
        paths.map! { |p| Pathname.new(p) }
        files = paths.select(&:file?)

        (paths - files).each do |dir|
          files << find_files(dir.children)
        end

        files.flatten.map(&:to_s)
      end

      def include_resource_path?(path, options)
        # Skip git files.
        return false if path =~ /\/\.git\//
        return true if options[:include_all]

        Percy::Cli::STATIC_RESOURCE_EXTENSIONS.include?(File.extname(path))
      end

      def include_root_path?(path, options)
        # Skip git files.
        return false if path =~ /\/\.git\//

        # Skip files that don't match the snapshots_regex.
        snapshots_regex = options[:snapshots_regex] || DEFAULT_SNAPSHOTS_REGEX
        path.match(snapshots_regex)
      end
    end
  end
end
