require "libhoney"

module Rack
  module Honeycomb
    # Prefix for attaching arbitrary metadata to the `env`. Will be deleted from
    # the `env` once it's pulled off of the `env` and onto a Honeycomb event.
    ENV_PREFIX = "honeycomb."

    class Middleware
      HEADER_REGEX = /^#{ Regexp.escape ENV_PREFIX }/

      attr_reader :app
      attr_reader :options

      ##
      # @param  [#call]                       app
      # @param  [Hash{Symbol => Object}]      options
      # @option options [String]  :writekey   (nil)
      # @option options [String]  :dataset    (nil)
      # @option options [String]  :api_host   (nil)
      def initialize(app, options = {})
        @app, @options = app, options
      end

      def honeycomb
        Thread.current[:honeycomb_client] ||= Libhoney::Client.new(:writekey => @options[:writekey],
                                                                   :dataset  => @options[:dataset],
                                                                   :api_host => @options[:api_host])
      end

      def add_field(ev, field, value)
        ev.add_field(field, value) if value != nil && value != ''
      end

      def add_env(ev, env, field)
        add_field(ev, field, env[field])
      end

      def call(env)
        ev = honeycomb.event
        request_started_at = Time.now
        status, headers, response = @app.call(env)
        request_ended_at = Time.now

        ev.add(headers)
        if headers['Content-Length'] != nil
          # Content-Length (if present) is a string.  let's change it to an int.
          ev.add_field('Content-Length', headers['Content-Length'].to_i)
        end
        add_field(ev, 'HTTP_STATUS', status)
        add_field(ev, 'REQUEST_TIME_MS', (request_ended_at - request_started_at) * 1000)

        # Pull arbitrary metadata off `env` if the caller attached anything
        # inside the Rack handler.
        env.each_pair do |k, v|
          if k.is_a?(String) && k.match(HEADER_REGEX)
            add_field(ev, k.sub(HEADER_REGEX, ''), v)
            env.delete(k)
          end
        end

        # we can't use `ev.add(env)` because json serialization fails.
        # pull out some interesting and potentially useful fields.
        add_env(ev, env, 'rack.version')
        add_env(ev, env, 'rack.multithread')
        add_env(ev, env, 'rack.multiprocess')
        add_env(ev, env, 'rack.run_once')
        add_env(ev, env, 'SCRIPT_NAME')
        add_env(ev, env, 'QUERY_STRING')
        add_env(ev, env, 'SERVER_PROTOCOL')
        add_env(ev, env, 'SERVER_SOFTWARE')
        add_env(ev, env, 'GATEWAY_INTERFACE')
        add_env(ev, env, 'REQUEST_METHOD')
        add_env(ev, env, 'REQUEST_PATH')
        add_env(ev, env, 'REQUEST_URI')
        add_env(ev, env, 'HTTP_VERSION')
        add_env(ev, env, 'HTTP_HOST')
        add_env(ev, env, 'HTTP_CONNECTION')
        add_env(ev, env, 'HTTP_CACHE_CONTROL')
        add_env(ev, env, 'HTTP_UPGRADE_INSECURE_REQUESTS')
        add_env(ev, env, 'HTTP_USER_AGENT')
        add_env(ev, env, 'HTTP_ACCEPT')
        add_env(ev, env, 'HTTP_ACCEPT_LANGUAGE')
        add_env(ev, env, 'REMOTE_ADDR')
        ev.send

        [status, headers, response]
      end
    end
  end
end
