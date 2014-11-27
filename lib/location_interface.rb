
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "httparty"
require "logger"

require_relative "email"
require_relative "address"
require_relative "google"

class LocationInterface < Sinatra::Base

    configure do
        set :dump_errors, true
        set :raise_errors, true
        set :show_exceptions, true

        contents = Psych.load_file "config/config.yaml"
        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["nominatim"]["service_url"]
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
        end
    end

    helpers Sinatra::JSON

    error Exception do
        puts "argh"
        exit 1
    end

    before do
        @logger ||= Logger.new "log/loggy.log", "daily"
        @logger.info "#{request.request_method} #{request.path} #{request.query_string} #{request.POST}"
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
        split_address = Address.split_street(params["address"])
        address_string = "#{split_address[:street_name]} #{split_address[:street_number]}, #{params[:postal_code]} #{params[:city]}"
        places = Nominatim.search(address_string).limit(1).address_details(true)
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found with given address"' ] if places.count < 1

        place = places.each.next

        hash = { latitude: place.lat, longitude: place.lon }
        json hash
    end

    # Arguments:
    # - latitude
    # - longitude
    post "/reverse" do
        place = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if place.nil?
        address = place.address
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if address.nil?

        hash = { "city" => address.city, "postal_code" => address.postcode }

        if not address.road
            Email.send( {
                from: "location_interface@slm.fi",
                to: "tekninen@slm.fi",
                subject: "Road missing in Nominatim result",
                message: "For some reason Nominatim result had road instead of street in the response. Debug this: #{place.inspect}"
            })
            #raise "Road not set in response. Response: #{place.inspect}"
        end

        if address.road
            hash["address"] = "#{address.road}"
            if address.house_number
                 hash["address"] += " #{address.house_number}"
            end
        end

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
    #
    # Returns distance in kilometers
    post "/distance_by_roads" do
        if params["from"].nil? or params["to"].nil?
            raise "Invalid input."
        end

        from = {}
        to = {}
        unless params["from"]["latitude"].nil?
            from["latitude"] = params["from"]["latitude"]
            from["longitude"] = params["from"]["longitude"]
        else
            from["latitude"], from["longitude"] = address_to_coordinates params["from"]
            return if from["latitude"].nil? # return in case we didn’t get proper result
        end

        unless params["to"]["latitude"].nil?
            to["latitude"] = params["to"]["latitude"]
            to["longitude"] = params["to"]["longitude"]
        else
            to["latitude"], to["longitude"] = address_to_coordinates params["to"]
            return if to["latitude"].nil? # return in case we didn’t get proper result
        end

        #@logger.info from
        #@logger.info to

        config = Psych.load_file "config/config.yaml"
        uri = "#{config["osrm"]["service_url"]}/viaroute?loc=#{from["latitude"]}," +
                "#{from["longitude"]}&loc=#{to["latitude"]},#{to["longitude"]}"
        #@logger.info uri
        response = HTTParty.get uri

        body = JSON.parse response.body

        distance = nil # distance in kilometers
        if body["status"] != 0
            # OSRM was not able to route us, so let’s try Google’s thingy instead
            google = Google.new
            distance = google.distance_by_roads to, from
            if distance.nil?
                @logger.error response.body
                status 404
                body "There was no route found between the given addresses"
                return
            end
        else
            distance = body["route_summary"]["total_distance"] / 1000.0
        end

        json distance
    end

    private

    def address_to_coordinates address
        split_address = Address.split_street(address["address"])
        street_address = "#{split_address[:street_name]} #{split_address[:street_number]}"
        unless address["city"].empty?
            address_string = "#{street_address}, #{address["city"]}"
        else
            address_string = "#{street_address}, #{address["postal_code"]}"
        end
        places = Nominatim.search(address_string).limit(1).address_details(true)
        if places.count < 1
            status 404
            body "No coordinates found for given address"
            return nil
        end

        place = places.each.next

        return place.lat, place.lon
    end

    run! if app_file == $0
end