
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "sqlite3"
require "digest/murmurhash"
require "exception_notification"

require_relative "email"
require_relative "address"
require_relative "google"
require_relative "osrm"

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
            config.api_key = contents["nominatim"]["api_key"] unless contents["nominatim"]["api_key"].nil? or !contents["nominatim"]["api_key"].empty?
        end
    end

    private

    def self.sqlite
        @@sqlite ||= nil
        return @@sqlite if not @@sqlite.nil?

        @@sqlite = SQLite3::Database.new "requests.sqlite3"
        @@sqlite.execute <<-SQL
        create table if not exists requests (
            id integer primary key,
            type varchar(50),
            input varchar(500),
            successful boolean,
            created_at datetime default current_timestamp
        );
        SQL

        @@sqlite.execute <<-SQL
        create table if not exists geocodes (
            id integer primary key,
            request_id integer,
            address varchar(50),
            postal_code varchar(50),
            city varchar(50),
            successful boolean,
            service_provider varchar(50),
            created_at datetime default current_timestamp
        );
        SQL

        @@sqlite.execute <<-SQL
        create table if not exists distance_calculations (
            id integer primary key,
            request_id integer,
            from_latitude decimal(15,10),
            from_longitude decimal(15,10),
            to_latitude decimal(15,10),
            to_longitude decimal(15,10),
            distance decimal(10,5),
            successful boolean,
            service_provider varchar(50),
            created_at datetime default current_timestamp
        );
        SQL

        @@sqlite
    end
end

# and finally construct the Rack application
class LocationInterface < Sinatra::Base
    use Rack::Config do |env|
        env["action_dispatch.parameter_filter"] = [:password]
    end

    use ExceptionNotification::Rack,
        email: {
            email_prefix: "[location_interface] ",
            sender_address: "\"location_interface\" <#{LocationInterface.config["error_email"]["sender_email"]}>",
            exception_recipients: [ LocationInterface.config["error_email"]["email"] ],
            smtp_settings: {
                address: LocationInterface.config["error_email"]["server"],
                port: LocationInterface.config["error_email"]["port"]
            }
        }

    configure do
        set :dump_errors, true
        set :raise_errors, true
        set :show_exceptions, false
        #set :show_exceptions, true # for debugging

        LocationInterface.configure_nominatim
    end

    helpers Sinatra::JSON

    error Exception do
        puts "argh"
        exit 1
    end

    before do
        expires 15 * 60, :public, :must_revalidate
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
        LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "geocode", params.inspect ]
        request_id = LocationInterface.sqlite.last_insert_row_id
        latitude, longitude = Address.address_to_coordinates params, request_id
        if latitude.nil?
            status 404
            body "No coordinates found for given address"
            return
        end
        hash = { latitude: latitude, longitude: longitude }

        LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id
        json hash
    end

    # Arguments:
    # - latitude
    # - longitude
    post "/reverse" do
        etag Digest::MurmurHash64A.hexdigest("#{params["latitude"]}#{params["longitude"]}"), new_resource: false, kind: :weak
        LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "reverse", params.inspect ]
        request_id = LocationInterface.sqlite.last_insert_row_id
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

        LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id

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
    # For address, at least postal code or city must be given, otherwise the result is not
    # accurate.
    #
    # If both address and coordinates are given, coordinates are preferred over address.
    #
    # Internally, address will be converted to coordinates and then routed using coordinates.
    #
    # Returns distance in kilometers
    post "/distance_by_roads" do
        LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "distance_by_roads", params.inspect ]
        request_id = LocationInterface.sqlite.last_insert_row_id

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
            from["latitude"], from["longitude"] = Address.address_to_coordinates params["from"], request_id
            return if from["latitude"].nil? # return in case we didn’t get proper result
        end

        unless params["to"]["latitude"].nil?
            to["latitude"] = params["to"]["latitude"]
            to["longitude"] = params["to"]["longitude"]
        else
            to["latitude"], to["longitude"] = Address.address_to_coordinates params["to"], request_id
            return if to["latitude"].nil? # return in case we didn’t get proper result
        end

        body = distance_by_roads_with_osrm from, to, request_id

        distance = nil # distance in kilometers
        if body["status"] != 0
            # OSRM was not able to route us, so let’s try Google’s thingy instead
            LocationInterface.sqlite.execute "INSERT INTO distance_calculations (request_id, from_latitude, from_longitude, to_latitude, to_longitude, service_provider) VALUES (?, ?, ?, ?, ?, ?)",
                    [ request_id, from["latitude"], from["longitude"], to["latitude"], to["longitude"], "google" ]
            distance_id = LocationInterface.sqlite.last_insert_row_id
            google = Google.new
            distance = google.distance_by_roads to, from
            if distance.nil?
                Email.error_email "Google wasn’t able to route us: #{response.body}"
                status 404
                body "There was no route found between the given addresses"
                return
            end
            LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, distance_id
        else
            # first request was ok
            distance = body["route_summary"]["total_distance"] / 1000.0

            LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, @distance_id
        end


        result = LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id

        json distance
    end

    private

    def distance_by_roads_with_osrm from, to, request_id

        config = LocationInterface.config
        LocationInterface.sqlite.execute "INSERT INTO distance_calculations (request_id, from_latitude, from_longitude, to_latitude, to_longitude, service_provider) VALUES (?, ?, ?, ?, ?, ?)",
                [ request_id, from["latitude"], from["longitude"], to["latitude"], to["longitude"], config["osrm"]["service_url"] ]
        @distance_id = LocationInterface.sqlite.last_insert_row_id

        OSRM.distance_by_roads from, to
    end

    run! if app_file == $0
end