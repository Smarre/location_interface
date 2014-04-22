
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "httparty"

require_relative "email"
require_relative "address"

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

    # Arguments:
    # - address
    # - city
    # - postal_code
    #
    # Either address or postal code is required, not both.
    post "/geocode" do
        address_string = "#{params["address"]}, #{params["postal_code"]} #{params["city"]}"
        places = Nominatim.search(address_string).limit(1).address_details(true)
        raise "No restaurants" if places.count < 1

        place = places.each.next

        hash = { latitude: place.lat, longitude: place.lon }
        json hash
    end

    # Arguments:
    # - latitude
    # - longitude
    post "/reverse" do
        place = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch
        raise "Nothing found for given coordinates" if place.nil?
        address = place.address
        if not address.road
            Email.send( {
                from: "location_interface@slm.fi",
                to: "tekninen@slm.fi",
                subject: "Road in Nominatim result instead of street",
                message: "For some reason Nominatim result had road instead of street in the response. Debug this: #{place.inspect}"
            })
            raise "Road not set in response. Response: #{place.inspect}"
        end
        hash = { "address" => "#{address.road} #{address.house_number}", "city" => address.city, "postal_code" => address.postcode }
        json hash
    end

    # distance from dot a to dot b over air
    post "/distance" do
        raise "Not implemented"
    end


    # Arguments:
    # - from["address"]
    # - from["postal_code"]
    # - from["city"]
    # - from["latitude"]
    # - from["longitude"]
    # - to["address"]
    # - to["postal_code"]
    # - to["city"]
    # - to["latitude"]
    # - to["longitude"]
    #
    # For address, atleast postal code or city must be given, otherwise the result is not
    # accurate.
    #
    # If both address and coordinates are given, coordinates are preferred over address.
    #
    # Internally, address will be converted to coordinates and then routed using coordinates.
    post "/distance_by_roads" do
        if params["from"].nil? or params["to"].nil?
            raise "Invalid input."
        end

        from = {}
        to = {}
        puts params
        unless params["from"]["latitude"].nil?
            from["latitude"] = params["from"]["latitude"]
            from["longitude"] = params["from"]["longitude"]
        else
            from["latitude"], from["longitude"] = address_to_coordinates params["from"]
        end

        unless params["to"]["latitude"].nil?
            to["latitude"] = to["to"]["latitude"]
            to["longitude"] = to["to"]["longitude"]
        else
            to["latitude"], to["longitude"] = address_to_coordinates params["to"]
        end

        config = Psych.load_file "config/config.yaml"
        uri = "#{config["osrm"]["service_url"]}/viaroute?loc=#{from["latitude"]}," +
                "#{from["longitude"]}&loc=#{to["latitude"]},#{to["longitude"]}"
        response = HTTParty.get uri

        body = JSON.parse response.body
        json body["route_summary"]["total_distance"]
    end

    private

    def address_to_coordinates address
        split_address = Address.split_street(address["address"])
        street_address = "#{split_address["street_name"]} #{split_address["street_number"]}"
        address_string = "#{street_address}, #{address["postal_code"]} #{address["city"]}"
        places = Nominatim.search(address_string).limit(1).address_details(true)
        raise "No coordinates found for given address" if places.count < 1

        place = places.each.next

        return place.lat, place.lon
    end

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