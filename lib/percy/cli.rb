require 'commander'
require 'percy'
require 'percy/cli/version'
require 'percy/cli/snapshot'

module Percy
  class Cli
    include Commander::Methods
    include Percy::Cli::Snapshot

    DEFAULT_NUM_THREADS = 3
    MAX_NUM_THREADS = 10

    def say(*args)
      $terminal.say(*args)
    end

    def say_error(*args)
      STDERR.puts *args
    end

    def run
      program :name, 'Percy CLI'
      program :version, Percy::Cli::VERSION
      program :description, 'Command-line interface for Percy (https://percy.io).'
      program :help_formatter, :compact
      default_command :help

      command :snapshot do |c|
        c.syntax = 'snapshot <root_dir>'
        c.description = 'Snapshot a folder of static files.'
        c.option \
          '--baseurl PATH',
          String,
          'The live URL base path. Defaults to "/". Set this if your site is hosted in ' +
          'a subdirectory in production that does not exist locally. If using Jekyll, this ' +
          'should be the same as your "baseurl" config.'
        c.option \
          '--strip_prefix PATH',
          String,
          'Directory path to strip from generated URLs. Defaults to the given root directory.'
        c.option \
          '--repo STRING',
          String,
          'Full GitHub repo slug (owner/repo-name). Defaults to the local git repo origin URL.'
        c.option \
          '--snapshots_regex REGEX',
          String,
          'Regular expression for matching the files to snapshot. Defaults to: "\.(html|htm)$"'
        c.option \
          '--snapshot_limit NUM',
          Integer,
          "Max number of snapshots to upload, useful for testing. Default is unlimited."
        c.option \
          '--threads NUM',
          Integer,
          "Number of threads in pools for snapshot and resource uploads. " +
          "Defaults to #{DEFAULT_NUM_THREADS}, max #{MAX_NUM_THREADS}."

        c.action do |args, options|
          options.default threads: DEFAULT_NUM_THREADS
          options.threads = MAX_NUM_THREADS if options.threads > MAX_NUM_THREADS

          raise OptionParser::MissingArgument, 'root folder path is required' if args.empty?
          if args.length > 1
            raise OptionParser::MissingArgument, 'only a single root folder path can be given'
          end
          root_dir = args.first

          run_snapshot(root_dir, options.__hash__)
        end
      end

      run!
    end
  end
end


