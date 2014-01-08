
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "net/smtp"

class LocationInterface < Sinatra::Base
    

    helpers Sinatra::JSON

    before do
        parse_config
    end

    error Exception do
        puts "argh"
        exit 1
    end

    get "/" do
        "Nya."
    end

    post "/geocode" do
        places = Nominatim.search(params["address_string"]).limit(1).address_details(true)
        return json "No restaurants" if places.count < 1

        place = places.each.next

        hash = { latitude: place.lat, longitude: place.lon }
        json hash
    end

    post "/reverse" do
        foobar
        place = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch
        return json "Nothing found for given coordinates" if place.nil?
        address = place.address
        if not address.road
            # TODO: send mail about this, there is most likely street instead of road, that case must be
            # handled somehow.
            raise "Road not set in response. Response: #{place.inspect}"
        end
        hash = { "address" => "#{address.road} #{address.house_number}", "city" => address.city, "postal_code" => address.postcode }
        json hash
    end

    private

    def parse_config
        contents = Psych.load_file "config/config.yaml"

        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["nominatim"]["service_url"]
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
        end
    end

    run! if app_file == $0

rescue Exception => e
    puts "nya"
    exit 1
    contents = Psych.load_file "config/config.yaml"

    unless contents["error_email"].nil?
        Net::SMTP.start contents["error_email"]["server"], contents["error_email"]["port"],
                contents["error_email"]["username"], contents["error_email"]["password"], contents["error_email"]["method"] do |smtp|
            sender_email = "dummy@email.nya"
            message = <<-EOF
            From: Location interface error catcher <#{sender_email}>
            To: <#{contents["error_email"]["email"]}>
            Subject: Error in location interface

            There was an error in location interface:

            #{e.message}

            Backtrace:
            #{e.backtrace}
            EOF
            smtp.send_message message, sender_email, contents["error_email"]["email"]
        end
    end

    raise e
end