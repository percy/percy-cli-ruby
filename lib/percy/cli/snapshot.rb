require 'find'
require 'digest'
require 'uri'

module Percy
  class Cli
    module Snapshot
      STATIC_RESOURCE_EXTENSIONS = [
        '.css', '.jpg', '.jpeg', '.gif', '.ico', '.png', '.bmp', '.pict', '.tif', '.tiff', '.ttf',
        '.eot', '.woff', '.otf', '.svg', '.svgz', '.webp', '.ps',
      ].freeze
      DEFAULT_SNAPSHOTS_REGEX = /\.(html|htm)$/

      def run_snapshot(root_dir, options = {})
        repo = options[:repo] || Percy.config.repo
        strip_prefix = File.absolute_path(options[:strip_prefix] || root_dir)

        # Create a Percy build for the snapshots.
        build = Percy.create_build(repo)

        # Find all the static files in the given root directory.
        root_paths = find_root_paths(root_dir, snapshots_regex: options[:snapshots_regex])
        resource_paths = find_resource_paths(root_dir)
        root_resources = build_resources(root_paths, strip_prefix, is_root: true)
        related_resources = build_resources(resource_paths, strip_prefix)

        # Upload a snapshot for every root resource, and associate the related_resources.
        root_resources.each_with_index do |root_resource, i|
          say "Uploading snapshot (#{i+1}/#{root_resources.length}): #{root_resource.resource_url}"
          upload_snapshot(build, root_resource, related_resources)
        end

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
          extension = File.extname(path)

          # Skip directories.
          next if !FileTest.file?(path)
          # Skip dot files.
          next if path.match(/\/\./)
          # Only include files with the above static extensions.
          next if !Percy::Cli::STATIC_RESOURCE_EXTENSIONS.include?(extension)

          file_paths << path
        end
        file_paths
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

      def upload_snapshot(build, root_resource, related_resources)
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
        missing_resources.each do |missing_resource|
          missing_resource_sha = missing_resource['id']
          resource = all_resources.find { |r| r.sha == missing_resource_sha }
          path = resource.resource_url
          bar.increment resource_url: resource.resource_url
          Percy.upload_resource(build['data']['id'], File.read("#{resource.path}"))
        end
      end
    end
  end
end