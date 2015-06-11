
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "httparty"
require "logger"
require "sqlite3"
require "digest/murmurhash"

require_relative "email"
require_relative "address"
require_relative "google"

# class methods; Sinatra requests uses wrapper class so they can’t be accessed directly anyway
class LocationInterface < Sinatra::Base
    def self.config
        @@config ||= Psych.load_file "config/config.yaml"
    end

    def self.configure_nominatim
        contents = self.config
        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["nominatim"]["service_url"]
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
        end
    end

    private

    def self.sqlite
        @@sqlite ||= nil
        return @@sqlite if not @@sqlite.nil?

        @@sqlite = SQLite3::Database.new "requests.sqlite3"
        @@sqlite.execute <<-SQL
        create table if not exists loggy (
            id integer primary key,
            service varchar(50),
            url varchar(100),
            timestamp datetime default current_timestamp
        );
        SQL

        @@sqlite
    end
end

# and finally construct the Rack application
class LocationInterface < Sinatra::Base

    configure do
        set :dump_errors, true
        set :raise_errors, true
        #set :show_exceptions, false
        set :show_exceptions, true # for debugging

        LocationInterface.configure_nominatim
    end

    helpers Sinatra::JSON

    error Exception do
        puts "argh"
        exit 1
    end

    before do
        expires 15 * 60, :public, :must_revalidate
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
        etag Digest::MurmurHash64A.hexdigest("#{params["address"]}#{params["city"]}#{params["postal_code"]}"), new_resource: false, kind: :weak
        latitude, longitude = Address.address_to_coordinates params
        if latitude.nil?
            status 404
            body "No coordinates found for given address"
            return
        end
        hash = { latitude: latitude, longitude: longitude }
        json hash
    end

    # Arguments:
    # - latitude
    # - longitude
    post "/reverse" do
        etag Digest::MurmurHash64A.hexdigest("#{params["latitude"]}#{params["longitude"]}"), new_resource: false, kind: :weak
        LocationInterface.sqlite.execute "INSERT INTO loggy (service, url) VALUES (?, ?)", [ "nominatim reverse", params.inspect ]
        place = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if place.nil?
        address = place.address
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if address.nil?

        city = address.city || address.town

        hash = { "city" => city, "postal_code" => address.postcode }

        if not address.road
            config = LocationInterface.config
            Email.send( {
                from: config["error_email"]["sender_email"],
                to: config["error_email"]["email"],
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

        etag Digest::MurmurHash64A.hexdigest("#{params["from"].to_s}#{params["to"].to_s}"), new_resource: false, kind: :weak

        from = {}
        to = {}
        unless params["from"]["latitude"].nil?
            from["latitude"] = params["from"]["latitude"]
            from["longitude"] = params["from"]["longitude"]
        else
            from["latitude"], from["longitude"] = Address.address_to_coordinates params["from"]
            return if from["latitude"].nil? # return in case we didn’t get proper result
        end

        unless params["to"]["latitude"].nil?
            to["latitude"] = params["to"]["latitude"]
            to["longitude"] = params["to"]["longitude"]
        else
            to["latitude"], to["longitude"] = Address.address_to_coordinates params["to"]
            return if to["latitude"].nil? # return in case we didn’t get proper result
        end

        body = LocationInterface.distance_by_roads_with_osrm from, to

        distance = nil # distance in kilometers
        if body["status"] != 0
            #
            # OSRM was not able to route us, so let’s try Google’s thingy instead
            google = Google.new
            distance = google.distance_by_roads to, from
            if distance.nil?
                Email.error_email "Google wasn’t able to route us: #{response.body}"
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

    def self.distance_by_roads_with_osrm from, to
        config = LocationInterface.config
        uri = "#{config["osrm"]["service_url"]}/viaroute?loc=#{from["latitude"]}," +
                "#{from["longitude"]}&loc=#{to["latitude"]},#{to["longitude"]}"
        #@logger.info uri
        LocationInterface.sqlite.execute "INSERT INTO loggy (service, url) VALUES (?, ?)", [ "osrm distance_by_roads", uri ]
        response = HTTParty.get uri

        JSON.parse response.body
    end

    run! if app_file == $0
end