require File.dirname(__FILE__) + "/lib/location_interface"
require File.dirname(__FILE__) + "/lib/email"

class App <  Sinatra::Application
    configure do
        # Don't log them. We'll do that ourself
        set :dump_errors, false

        # Don't capture any errors. Throw them up the stack
        set :raise_errors, true

        # Disable internal middleware for presenting errors
        # as useful HTML pages
        set :show_exceptions, false
    end
end

class ExceptionHandling
    def initialize(app)
        @app = app
    end

    def call(env)
        begin
            @app.call env
        rescue => e
            contents = Psych.load_file "config/config.yaml"

            unless contents["error_email"].nil?

                sender_email = "location-error-mailer@slm.fi"

                message = <<-EOF
                There was an error in location interface:

                #{e.message}

                Backtrace:
                #{e.backtrace.join "\n"}
                EOF

                res = Email.send({
                    from: sender_email,
                    to: contents["error_email"]["email"],
                    subject: "Error in location interface",
                    message: message
                })

                puts res

                [ 500, { "Content-Type" => "text/plain" }, "There was something terribly wrong. Please contact the admins." ]
            else
                [ 500, { "Content-Type" => "text/plain" }, "There was something too terribly wrong. Please contact the admins." ]
            end
        end
    end
end

use ExceptionHandling
#run App
run LocationInterface.new