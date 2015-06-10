require 'find'
require 'digest'
require 'uri'
require 'thread/pool'

module Percy
  class Cli
    module Snapshot
      # Static resource types that an HTML file might load and that we want to upload for rendering.
      STATIC_RESOURCE_EXTENSIONS = [
        '.css', '.jpg', '.jpeg', '.gif', '.ico', '.png', '.bmp', '.pict', '.tif', '.tiff', '.ttf',
        '.eot', '.woff', '.otf', '.svg', '.svgz', '.webp', '.ps',
      ].freeze

      DEFAULT_SNAPSHOTS_REGEX = /\.(html|htm)$/

      # Modified version of Diego Perini's URL regex. https://gist.github.com/dperini/729294
      REMOTE_URL_REGEX_STRING = (
        # protocol identifier
        "(?:(?:https?:)?//)" +
        "(?:" +
          # IP address exclusion
          # private & local networks
          "(?!(?:10|127)(?:\\.\\d{1,3}){3})" +
          "(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})" +
          "(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})" +
          # IP address dotted notation octets
          # excludes loopback network 0.0.0.0
          # excludes reserved space >= 224.0.0.0
          # excludes network & broacast addresses
          # (first & last IP address of each class)
          "(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])" +
          "(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}" +
          "(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))" +
        "|" +
          # host name
          "(?:(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)" +
          # domain name
          "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*" +
          # TLD identifier
          "(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))" +
        ")" +
        # port number
        "(?::\\d{2,5})?" +
        # resource path
        "(?:/[^\\s\"']*)?"
      )
      HTML_REMOTE_URL_REGEX = Regexp.new("(<link.*?href=['\"](" + REMOTE_URL_REGEX_STRING + ")[^>]+)")

      # Match all url("https://...") calls, with whitespace and quote variatinos.
      CSS_REMOTE_URL_REGEX = Regexp.new(
        "url\\s*\\([\"'\s]*(" + REMOTE_URL_REGEX_STRING + ")[\"'\s]*\\)"
      )

      def run_snapshot(root_dir, options = {})
        repo = options[:repo] || Percy.config.repo
        strip_prefix = File.absolute_path(options[:strip_prefix] || root_dir)
        autoload_remote_resources = options[:autoload_remote_resources] || false
        num_threads = options[:threads] || 10

        # Find all the static files in the given root directory.
        root_paths = find_root_paths(root_dir, snapshots_regex: options[:snapshots_regex])
        resource_paths = find_resource_paths(root_dir)
        root_resources = build_resources(root_paths, strip_prefix, is_root: true)
        related_resources = build_resources(resource_paths, strip_prefix)

        if autoload_remote_resources
          remote_urls = find_remote_urls(root_paths + resource_paths)
          related_resources += build_remote_resources(remote_urls)
        end


        if root_resources.empty?
          say "No root resource files found. Are there HTML files in the given directory?"
          exit(-1)
        end

        # Create a Percy build for the snapshots.
        build = Percy.create_build(repo)

        # Upload the first snapshot synchronously since many resources are likely shared.
        root_resource = root_resources[0]
        say "Uploading snapshot (1/#{root_resources.length}): #{root_resource.resource_url}"
        upload_snapshot(build, root_resource, related_resources, {num_threads: num_threads})

        # Upload a snapshot for every root resource, and associate the related_resources.
        output_lock = Mutex.new
        snapshot_thread_pool = Thread.pool(num_threads)
        root_resources[1..-1].each_with_index do |root_resource, i|
          snapshot_thread_pool.process do
            output_lock.synchronize do
              say "Uploading snapshot (#{i+2}/#{root_resources.length}): #{root_resource.resource_url}"
            end
            upload_snapshot(build, root_resource, related_resources, {num_threads: num_threads})
          end
        end

        snapshot_thread_pool.wait
        snapshot_thread_pool.shutdown

        # Finalize the build.
        Percy.finalize_build(build['data']['id'])
      end

      private

      def find_root_paths(dir_path, options = {})
        snapshots_regex = options[:snapshots_regex] || DEFAULT_SNAPSHOTS_REGEX

        file_paths = []
        Find.find(dir_path).each do |relative_path|
          path = File.absolute_path(relative_path)
          # Skip directories.
          next if !FileTest.file?(path)
          # Skip files that don't match the snapshots_regex.
          next if !path.match(snapshots_regex)
          file_paths << path
        end
        file_paths
      end

      def find_resource_paths(dir_path)
        file_paths = []
        Find.find(dir_path).each do |relative_path|
          path = File.absolute_path(relative_path)

          # Skip directories.
          next if !FileTest.file?(path)
          # Skip dot files.
          next if path.match(/\/\./)
          # Only include files with the above static extensions.
          next if !Percy::Cli::STATIC_RESOURCE_EXTENSIONS.include?(File.extname(path))

          file_paths << path
        end
        file_paths
      end

      def find_remote_urls(file_paths)
        urls = []
        file_paths.each do |path|
          extension = File.extname(path)
          case extension
          when '.html'
            content = File.read(path)
            urls += content.scan(HTML_REMOTE_URL_REGEX).map do |match|
              next if !match[0].include?('stylesheet')  # Only include links with rel="stylesheet".
              maybe_add_protocol(match[1])
            end
          when '.css'
            content = File.read(path)
            urls += content.scan(CSS_REMOTE_URL_REGEX).map { |match| maybe_add_protocol(match[0]) }
          end
        end
        urls.compact.uniq
      end

      def maybe_add_protocol(url)
        url[0..1] == '//' ? "http:#{url}" : url
      end

      def build_resources(paths, strip_prefix, options = {})
        resources = []

        # Strip trailing slash from strip_prefix.
        strip_prefix = strip_prefix[0..-2] if strip_prefix[-1] == '/'

        paths.each do |path|
          sha = Digest::SHA256.hexdigest(File.read(path))
          resource_url = URI.escape(path.sub(strip_prefix, ''))
          resources << Percy::Client::Resource.new(
            resource_url, sha: sha, is_root: options[:is_root], path: path)
        end
        resources
      end

      def build_remote_resources(remote_urls)
        resources = []

        bar = Commander::UI::ProgressBar.new(
          remote_urls.length,
          title: 'Fetching remote resources...',
          format: ':title |:progress_bar| :percent_complete% complete - :url',
          width: 40,
          complete_message: nil,
        )

        remote_urls.each do |url|
          bar.increment url: url
          begin
            response = Faraday.get(url)
          rescue Faraday::Error::ConnectionFailed => e
            say_error e
            next
          end
          if response.status != 200
            say_error "Remote resource failed, skipping (#{response.status}): #{url}"
            next
          end

          sha = Digest::SHA256.hexdigest(response.body)
          resources << Percy::Client::Resource.new(url, sha: sha, content: response.body)
        end
        resources
      end

      def upload_snapshot(build, root_resource, related_resources, options = {})
        all_resources = [root_resource] + related_resources

        # Create the snapshot for this page. For simplicity, include all non-HTML resources in the
        # snapshot as related resources. May seem inefficient, but they will only be uploaded once.
        snapshot = Percy.create_snapshot(build['data']['id'], all_resources)

        # Upload the content for any missing resources.
        missing_resources = snapshot['data']['relationships']['missing-resources']['data']
        bar = Commander::UI::ProgressBar.new(
          missing_resources.length,
          title: 'Uploading resources...',
          format: ':title |:progress_bar| :percent_complete% complete - :resource_url',
          width: 40,
          complete_message: nil,
        )
        output_lock = Mutex.new
        uploader_thread_pool = Thread.pool(options[:num_threads] || 10)
        missing_resources.each do |missing_resource|
          uploader_thread_pool.process do
            missing_resource_sha = missing_resource['id']
            resource = all_resources.find { |r| r.sha == missing_resource_sha }
            path = resource.resource_url
            output_lock.synchronize do
              bar.increment resource_url: resource.resource_url
            end

            # Remote resources are stored in 'content', local resources are read from the filesystem.
            content = resource.content || File.read("#{resource.path}")

            Percy.upload_resource(build['data']['id'], content)
          end
        end
        uploader_thread_pool.wait
        uploader_thread_pool.shutdown
      end
    end
  end
end