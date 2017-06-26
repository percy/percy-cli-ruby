module Percy
  class Cli
    class Client
      module UserAgent
        def _client_info
          "percy-cli/#{VERSION}"
        end
      end
    end
  end
end
