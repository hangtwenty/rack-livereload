require 'erb'

module Rack
  class LiveReload
    LIVERELOAD_JS_PATH = '/__rack/livereload.js'
    LIVERELOAD_LOCAL_URI = 'http://localhost:35729/livereload.js'

    attr_reader :app

    def initialize(app, options = {})
      @app = app
      @options = options
    end

    def use_vendored?
      return @use_vendored if @use_vendored

      if @options[:source]
        @use_vendored = (@options[:source] == :vendored)
      else
        require 'net/http'
        require 'uri'

        uri = URI.parse(LIVERELOAD_LOCAL_URI)

        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 1

        begin
          http.send_request('GET', uri.path)
          @use_vendored = false
        rescue Timeout::Error, Errno::ECONNREFUSED, EOFError
          @use_vendored = true
        rescue => e
          $stderr.puts e.inspect
          raise e
        end
      end

      @use_vendored
    end

    def call(env)
      _, path, file = (env['PATH_INFO'] || '').split('/')

      if path == '__rack' && ::File.file?(target = ::File.expand_path("../../../js/#{file}", __FILE__))
        deliver_file(target)
      else
        status, headers, body = @app.call(env)

        if !@options[:ignore] || !@options[:ignore].any? { |filter| path[filter] }
          case headers['Content-Type']
          when %r{text/html}
            content_length = 0

            body.each do |line|
              if !headers['X-Rack-LiveReload'] && line['</head>']
                host_to_use = (@options[:host] || env['HTTP_HOST'] || 'localhost').gsub(%r{:.*}, '')

                if use_vendored?
                  src = LIVERELOAD_JS_PATH.dup + "?host=#{host_to_use}"
                else
                  src = LIVERELOAD_LOCAL_URI.dup.gsub('localhost', host_to_use) + '?'
                end

                src << "&mindelay=#{@options[:min_delay]}" if @options[:min_delay]
                src << "&maxdelay=#{@options[:max_delay]}" if @options[:max_delay]
                src << "&port=#{@options[:port]}" if @options[:port]

                template = ERB.new(::File.read(::File.expand_path('../../../skel/livereload.html.erb', __FILE__)))

                line.gsub!('</head>', %{#{template.result(binding)}</head>})

                headers["X-Rack-LiveReload"] = '1'
              end

              content_length += line.length
            end

            headers['Content-Length'] = content_length.to_s
          end
        end

        [ status, headers, body ]
      end
    end

    private
    def deliver_file(file)
      type = case ::File.extname(file)
             when '.js'
               'text/javascript'
             when '.swf'
               'application/swf'
             end

      [ 200, { 'Content-Type' => type, 'Content-Length' => ::File.size(file).to_s }, [ ::File.read(file) ] ]
    end

    def force_swf?
      @options[:force_swf]
    end

    def with_swf?
      !@options[:no_swf]
    end
  end
end

