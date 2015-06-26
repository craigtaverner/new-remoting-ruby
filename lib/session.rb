require 'logger'
require 'uri'
#require 'neo4j'

require './lib/pack_stream'
require './lib/chunk_writer_io'

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
        init: 0x01,
        ack_failure: 0x0F,
        run: 0x10,
        discard_all: 0x2F,
        pull_all: 0x3F,

        # server message types
        success: 0x70,
        record: 0x71,
        ignored: 0x7E,
        failure: 0x7F
      }

      CODE_TYPES = TYPE_CODES.invert

      def initialize(type_or_code, *args)
        @type_code = Message.type_code_for(type_or_code)
        fail "Invalid message type: #{@type_code.inspect}" if !@type_code
        @type = CODE_TYPES[@type_code]

        @args = args
      end

      def struct
        [@type_code, *@args].freeze
      end

      def packed_stream
        PackStream::Packer.new(struct).packed_stream
      end

      def value
        return if @type != :record
        @args.map do |arg|
          # Assuming result is Record
          field_names = arg[1]

          field_values = arg[2].map do |field_value|
            Message.interpret_field_value(field_value)
          end

          Hash[field_names.zip(field_values)]
        end
      end

      attr_reader :type, :args

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
      def initialize(session)
        @messages = []
        @session = session
      end

      def add_message(type, *args)
        @messages << Message.new(type, *args)
      end

      def chunked_packed_stream
        io = ChunkWriterIO.new

        @messages.each do |message|
          @session.logger.debug "#{message.type.to_s.upcase} #{message.args.join(' ')}"
          puts "WRITING: #{message.packed_stream.inspect}"
          io.write(message.packed_stream)
          io.flush(true)
        end

        io.rewind
        io.read
      end
    end

    def initialize(options = {})
      @options = options

      open_socket

      #@id = new_session_id

      #@session_path = BASE_SESSION_PATH + "/#{@id}"
    end

    def query(cypher, params = {})
      job = new_job
      job.add_message(:run, cypher, params)
      job.add_message(:pull_all)

      messages = send_job(job)
      handle_failure!(messages[0])
      fields = messages[0].args[0]['fields']

      result = flush_messages.map do |message|

        message.args.each_with_index.each_with_object({}) do |(arg, i), h|
          metadata, props = arg
          something, identifier, labels = metadata

          h[fields[i]] = props
        end
      end

      handle_failure!(flush_messages[0])

      result
    end

    def handle_failure!(message)
      if message.type == :failure
        job = new_job
        job.add_message(:ack_failure)
        send_job(job)

        fail "Cypher query failed: #{messages[0].args.inspect}"
      end
    end

    def response_messages(body)
      stream = StringIO.new(body)
      [].tap do |messages|
        until stream.eof?
          data = PackStream::Unpacker.new(stream).unpack_value!
          type_code, result = data

          messages << Message.new(type_code, result)
        end
      end
    end

    def close
      socket.delete(@session_path)
    end

    def logger
      @logger ||= Logger.new(logger_location).tap do |logger|
        logger.level = logger_level
      end
    end

    SUPPORTED_VERSIONS = [1, 0, 0, 0]
    VERSION = '0.0.1'
    USER_AGENT = "Ruby neo4j-ndp#{VERSION}"

    private

    def new_job
      Job.new(self)
    end

    def open_socket
      @socket = TCPSocket.open(server_host, server_port)

      handshake

      init
    end

    def handshake
      logger.debug('HANDSHAKE:')

      sendmsg(SUPPORTED_VERSIONS.pack("l>*"))

      agreed_version = @socket.recv(4).unpack("l>*")[0]

      if agreed_version.zero?
        @socket.shutdown(Socket::SHUT_RDWR)
        @socket.close

        fail "Couldn't agree on a version (Sent versions #{SUPPORTED_VERSIONS.inspect})"
      end

      logger.info "Agreed to version: #{agreed_version}"
    end

    def init
      job = new_job
      job.add_message(:init, USER_AGENT)

      send_job(job).tap do |response|
        fail "INIT didn't succeed.  Response: #{response.inspect}" if response[0].type != :success
      end
    end

    # Takes a Job object.
    # Sends it's messages to the server and returns an array of Message objects
    def send_job(job)
      sendmsg(job.chunked_packed_stream)

      flush_messages
    end

    def sendmsg(message)
      logger.debug "C: #{message.inspect}"

      @socket.sendmsg(message)
    end

    def flush_messages
      flush_response.map do |args|
        Message.new(args[0][0], *args[1..-1]).tap do |message|
          logger.debug "#{message.type.to_s.upcase} #{message.args.join(' ')}"
        end
      end
    end

    def flush_response
      result = []

      while (header = @socket.recv(2)).size > 0 && (chunk_size = header.unpack('s>*')[0]) > 0
        logger.debug "S: #{header.inspect}"
        logger.debug "Chunk size: #{chunk_size}"

        chunk = @socket.recv(chunk_size)
        logger.debug "S: #{chunk.inspect}"

        unpacker = PackStream::Unpacker.new(StringIO.new(chunk))

        result << []
        require 'pry'
        binding.pry
        while arg = unpacker.unpack_value!
          result[-1] << arg
        end
      end

      result
    end

    def server_base_url
      "http://#{server_host}:#{server_port}"
    end

    def server_host
      @options[:host] || 'localhost'
    end

    def server_port
      @options[:port] || 7687
    end

    def logger_location
      @options[:logger_location] || STDOUT
    end

    def logger_level
      @options[:logger_level] || Logger::WARN
    end
  end
end

#neo4j_session = Neo4j::Session.new(port: 7687)

#require 'awesome_print'
#ap neo4j_session.query("CREATE (a:Person {name:'Alice'})
#                       RETURN a, labels(a), a.name")
#
#ap neo4j_session.query('MATCH n, o RETURN n, o LIMIT 3')
#
#neo4j_session.close
