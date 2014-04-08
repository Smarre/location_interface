require 'bundler'
require 'childprocess'
require 'timeout'
require 'httparty'

begin
    Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
    $stderr.puts e.message
    $stderr.puts "Run `bundle install` to install missing gems"
    exit e.status_code
end

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../../lib')
require 'location_interface'

server = ChildProcess.build("rackup", "--port", "9999")
#server.io.inherit! # enable for interface debugging
server.start

begin
    Timeout.timeout(3) do
        loop do
            begin
                HTTParty.get('http://localhost:9999')
                break
            rescue Errno::ECONNREFUSED => try_again
                sleep 0.1
            end
        end
    end
rescue Timeout::Error => e
    puts "HTTParty.get('http://localhost:9999') failed"
    exit 1
end

at_exit do
    server.stop
end

