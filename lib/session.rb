require 'faraday'
require 'uri'
require './lib/pack_stream'
require 'neo4j'

module Neo4j
  # Implementing a fresh Neo4j Session object.
  # May replace the one in neo4j-core, but for now is just for
  # implementing PackStream
  class Session
    BASE_SESSION_PATH = '/session'

    DEFAULT_HEADERS = {
      'Connection' => 'keep-alive',
      'Content-Type' => 'application/vnd.neo4j.v1+packstream',
      'User-Agent' => 'neo4j-python/1.0'
    }

    # Represents messages sent to or received from the server
    class Message
      TYPE_CODES = {
        # client message types
        ack_failure: 0x0F,
        run: 0x10,
        discard_all: 0x2F,
        pull_all: 0x3F,

        # server message types
        success: 0x70,
        item: 0x71,
        ignored: 0x7E,
        failure: 0x7F
      }

      CODE_TYPES = TYPE_CODES.invert

      def initialize(type_or_code, correlation_id, *args)
        @type_code = Message.type_code_for(type_or_code)
        fail 'Invalid message type' if !@type_code
        @type = CODE_TYPES[@type_code]

        @correlation_id = correlation_id
        @args = args
      end

      def struct
        [@type_code, @correlation_id, *@args].freeze
      end

      def packed_stream
        PackStream::Packer.new(struct).packed_stream
      end

      def value
        return if @type != :item
        @args.map do |arg|
          # Assuming result is Record
          field_names = arg[1]
          # require 'pry'
          # binding.pry
          field_values = arg[2].map do |field_value|
            Message.interpret_field_value(field_value)
          end

          Hash[field_names.zip(field_values)]
        end
      end

      def self.pack(messages)
        messages.map(&:packed_stream).join
      end

      def self.type_code_for(type_or_code)
        type_or_code.is_a?(Integer) ? type_or_code : TYPE_CODES[type_or_code]
      end

      def self.interpret_field_value(value)
        if value.is_a?(Array) && (1..3).include?(value[0])
          case value[0]
          when 1
            {type: :node, identity: value[1],
             labels: value[2], properties: value[3]}
          end
        else
          value
        end
      end
    end

    # Represents a set of messages to send to the server
    class Job
      def initialize
        @messages = []
      end

      def add_message(type, correlation_id, *args)
        @messages << Message.new(type, correlation_id, *args)
      end

      def packed_stream
        Message.pack(@messages)
      end
    end

    def initialize(options = {})
      @options = options

      @id = new_session_id

      @session_path = BASE_SESSION_PATH + "/#{@id}"
    end

    def query(cypher, params = {})
      job = Job.new
      job.add_message(:run, 1, cypher, params)
      job.add_message(:pull_all, 2)

      response = connection.post(@session_path,
                                 job.packed_stream,
                                 DEFAULT_HEADERS)

      validate_status!(response)

      response_messages(response.body).map(&:value)
    end

    def response_messages(body)
      stream = StringIO.new(body)
      [].tap do |messages|
        until stream.eof?
          data = PackStream::Unpacker.new(stream).unpack_value!
          type_code, correlation_id, result = data

          messages << Message.new(type_code, correlation_id, result)
        end
      end
    end

    def close
      connection.delete(@session_path).tap do |response|
        validate_status!(response)
      end
    end

    def connection
      @connection ||= Faraday.new(url: server_base_url) do |faraday|
        faraday.adapter Faraday.default_adapter  # make requests with Net::HTTP
      end
    end

    private

    def new_session_id
      response = connection.post(BASE_SESSION_PATH)
      validate_status!(response, 201)

      response.headers['Location'].match(%r{/session/([^\/]+)})[1]
    end

    def validate_status!(request, expected_status = 200)
      return if request.status == expected_status

      fail <<MSG
Expected status #{expected_status}, got #{request.status}
For #{request.env.method.to_s.upcase} #{request.env.url}"
MSG
    end

    def server_base_url
      "http://#{server_host}:#{server_port}"
    end

    def server_host
      @options[:host] || 'localhost'
    end

    def server_port
      @options[:port] || 7474
    end
  end
end

neo4j_session = Neo4j::Session.new(port: 7687)

require 'awesome_print'
ap neo4j_session.query("CREATE (a:Person {name:'Alice'})
                       RETURN a, labels(a), a.name")

ap neo4j_session.query('MATCH n, o RETURN n, o LIMIT 3')

neo4j_session.close
