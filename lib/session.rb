require 'faraday'
require 'uri'
require 'pack_stream'

module Neo4j
  # Implementing a fresh Neo4j Session object.
  # May replace the one in neo4j-core, but for now is just for
  # implementing PackStream
  class Session
    def initialize(url)
      @uri = URI(url)

      @id = new_session_id
    end

    private

    def new_session_id
      connection.post('/session/').tap do |response|
        response.headers['location'].match(%r{/session/([^\/]+)})[1]
      end
    end

    def connection
      @connection ||= Faraday.new(url: base_url) do |faraday|
        faraday.adapter Faraday.default_adapter  # make requests with Net::HTTP
      end
    end

    def base_url
      @uri.to_s.gsub(/#{@uri.path}$/, '')
    end
  end
end

neo4j_session = Neo4j::Session.new('http://localhost:7687')
