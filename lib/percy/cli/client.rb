require 'percy/cli/client/user_agent'

module Percy
  class Cli
    class Client
      include Percy::Cli::Client::UserAgent

      attr_reader :client

      def initialize
        @client = Percy.client(client_info: _client_info, environment_info: _environment_info)
      end
    end
  end
end
