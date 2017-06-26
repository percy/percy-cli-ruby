module Percy
  class Cli
    class Client
      module UserAgent
        def _client_info
          "percy-cli/#{VERSION}"
        end

        def _environment_info
          [
            "middleman/#{_middleman_version}",
            "jekyll/#{_jekyll_version}",
          ].reject do |info|
            info =~ %r{\/$} # reject if version is empty
          end.join('; ')
        end

        def _middleman_version
          begin
            require 'middleman-core/version'
            Middleman::VERSION if defined? Middleman
          rescue LoadError; end
        end

        def _jekyll_version
          begin
            require 'jekyll/version'
            Jekyll::VERSION if defined? Jekyll
          rescue LoadError; end
        end
      end
    end
  end
end
