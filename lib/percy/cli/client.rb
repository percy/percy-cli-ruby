require 'percy/cli/client/user_agent'

module Percy
  class Cli
    class Client
      include Percy::Cli::Client::UserAgent

      attr_reader :client

      def initialize
        # environment_info is empty because we can't tell reliably from raw HTML files what versions
        # of which frameworks were used to generate them.
        @client = Percy.client(client_info: _client_info, environment_info: '')
      end
    end
  end
end
