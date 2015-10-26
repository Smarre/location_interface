require "net/smtp"
require "base64"

class Email

    def self.send(opts = {})

        return false, "from" if opts[:from].nil?
        return false, "to" if opts[:to].nil?
        return false, "subject" if opts[:subject].nil?
        return false, "message" if opts[:message].nil?

        from = "From: #{opts[:from]}"
        if not opts[:from_name].nil?
            from_alias = opts[:from_name]
            from = "From: #{from_alias} <#{opts[:from]}>"
        end

        to = "To: #{opts[:to]}"
        if not opts[:to_name].nil?
            to_alias = opts[:to_name]
            to = "To: #{to_alias} <#{opts[:to]}>"
        end

        subject = opts[:subject]
        message = opts[:message]

        subject = "Subject: =?UTF-8?B?" + Base64.strict_encode64(subject) + "?="

        begin
            Net::SMTP.start(LocationInterface.config["error_email"]["server"], LocationInterface.config["error_email"]["port"]) do |smtp|
                smtp.open_message_stream opts[:from], opts[:to] do |f|

                    f.puts "Content-type: text/plain; charset=UTF-8"
                    f.puts from
                    f.puts to
                    f.puts subject
                    f.puts
                    f.puts
                    f.puts message
                end
            end
        rescue Net::SMTPFatalError => error
            puts "Were not able to send email to location: #{to}"
            puts "Server reported following error:"
            puts error
            puts
            puts "Stack:"
            puts error.backtrace
        end

        true
    end

    def self.error_email message
        config = LocationInterface.config
        Email.send( {
                from: config["error_email"]["sender_email"],
                to: config["error_email"]["email"],
                subject: "location_interface encountered an error",
                message: message
            })
    end

end
