
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"
require "sqlite3"
require "digest/murmurhash"

require_relative "../config/initializers/errbit.rb"

require_relative "email"
require_relative "address"
require_relative "google"
require_relative "osrm"

class Notice < RuntimeError
end

# class methods; Sinatra requests uses wrapper class so they can’t be accessed directly anyway
class LocationInterface < Sinatra::Base

    use Airbrake::Rack::Middleware

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

    configure do
        #set :dump_errors, true
        #set :raise_errors, true
        set :show_exceptions, false
        #disable :show_exceptions
        #set :show_exceptions, true # for debugging

        #set :dump_errors, false
        #set :raise_errors, false

        LocationInterface.configure_nominatim
    end

    helpers Sinatra::JSON

    #error Exception do
    #    puts "argh"
    #    exit 1
    #end

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
        #LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "geocode", params.to_s ]
        #request_id = LocationInterface.sqlite.last_insert_row_id
        request_id = 0
        latitude, longitude = Address.address_to_coordinates params, request_id
        if latitude.nil?
            status 404
            body "No coordinates found for given address"
            return
        end
        hash = { latitude: latitude, longitude: longitude }

        #LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id
        json hash
    end

    # Takes hash of addresses as input:
    #
    # { "addresses" => { address_id => { "address" => .., "city" => .. }, .. } }
    #
    # Returns JSON hash of address_id => latitude/longitude pairs
    post "/multi_geocode" do
        etag Digest::MurmurHash64A.hexdigest("#{params["addresses"].to_s}"), new_resource: false, kind: :weak

        unless params["addresses"].respond_to? :each
            status 400
            body "Please give proper input"
            return
        end

        results = {}
        threads = []

        params["addresses"].each do |key, address|

            thread = Thread.new do

                if address.nil?
                    status 400
                    body "Please give somewhat more proper input"
                    return
                end

                if address["address"].nil?
                    status 400
                    body "Please give more proper input"
                    return
                end

                #LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "multi_geocode", params.to_s ]
                #request_id = LocationInterface.sqlite.last_insert_row_id
                request_id = 0
                latitude, longitude = Address.address_to_coordinates address, request_id
                if latitude.nil?
                    status 404
                    body "No coordinates found for given address"
                    return
                end
                hash = { latitude: latitude, longitude: longitude }
                results[key] = hash

                #LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id

            end

            threads << thread

        end

        threads.each { |thr| thr.join }

        json results
    end

    # Arguments:
    # - latitude
    # - longitude
    post "/reverse" do
        etag Digest::MurmurHash64A.hexdigest("#{params["latitude"]}#{params["longitude"]}"), new_resource: false, kind: :weak
        LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "reverse", params.to_s ]
        request_id = LocationInterface.sqlite.last_insert_row_id
        place = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if place.nil?
        address = place.address
        return [ 404, { "Content-Type" => "application/json" }, '"Nothing found for given coordinates"' ] if address.nil?

        city = address.city || address.town || address.village

        hash = { "city" => city, "postal_code" => address.postcode }

        if not address.road
            config = LocationInterface.config
            Airbrake.notify(Notice.new("For some reason Nominatim result had road instead of street in the response.")) do |notice|
                notice[:params][:place] = place.inspect
                notice[:context][:severity] = "info"
            end
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
        #LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "distance_by_roads", params.to_s ]
        #request_id = LocationInterface.sqlite.last_insert_row_id
        request_id = 0

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

        json distance_by_roads_osrm_first from, to, request_id
        #json distance_by_roads_google_first from, to, request_id
    end

    # TODO: there is /table service on OSRM which may do something we want to do about this. Should be investigated whether it would give good speedup.
    #
    # Takes addresses in in following format:
    #
    # { "addresses" => { address_id => { "from" => address_array, "to" => address_array }, .. } }
    #
    # Returns 404 if there is a problems with geocoding the input address.
    post "/multi_distance_by_roads" do
        etag Digest::MurmurHash64A.hexdigest("#{params["addresses"].to_s}"), new_resource: false, kind: :weak

        puts params.to_s

        unless params["addresses"].respond_to? :each
            status 400
            body "Please give proper input"
            return
        end

        results = {}
        threads = []

        params["addresses"].each do |key, address|

            thread = Thread.new do
                #LocationInterface.sqlite.execute "INSERT INTO requests (type, input) VALUES (?, ?)", [ "distance_by_roads", params.to_s ]
                #request_id = LocationInterface.sqlite.last_insert_row_id
                request_id = 0

                if address.nil? or address["from"].nil? or address["to"].nil?
                    raise "Invalid input."
                end

                from = {}
                to = {}
                unless address["from"]["latitude"].nil?
                    from["latitude"] = address["from"]["latitude"]
                    from["longitude"] = address["from"]["longitude"]
                else
                    from["latitude"], from["longitude"] = Address.address_to_coordinates address["from"], request_id
                    return if from["latitude"].nil? # return in case we didn’t get proper result
                end

                unless address["to"]["latitude"].nil?
                    to["latitude"] = address["to"]["latitude"]
                    to["longitude"] = address["to"]["longitude"]
                else
                    to["latitude"], to["longitude"] = Address.address_to_coordinates address["to"], request_id
                    return if to["latitude"].nil? # return in case we didn’t get proper result
                end

                results[key] = distance_by_roads_osrm_first from, to, request_id
                #results[key] = distance_by_roads_google_first from, to, request_id
            end

            threads << thread
        end

        threads.each { |thr| thr.join }

        json results
    end

    private

    def distance_by_roads_google_first from, to, request_id
        LocationInterface.sqlite.execute "INSERT INTO distance_calculations (request_id, from_latitude, from_longitude, to_latitude, to_longitude, service_provider) VALUES (?, ?, ?, ?, ?, ?)",
                [ request_id, from["latitude"], from["longitude"], to["latitude"], to["longitude"], "google" ]
        distance_id = LocationInterface.sqlite.last_insert_row_id
        google = Google.new
        distance = google.distance_by_roads to, from
        if not distance.nil?
            LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, distance_id
            return distance
        end

        body = distance_by_roads_with_osrm from, to, request_id

        distance = nil # distance in kilometers
        if body["status"] != 200
            Airbrake.notify(Notice.new("Neither Google or OSRM was able to route us")) do |notice|
                notice[:params][:response] = response.body
                notice[:context][:severity] = "error"
            end
            status 404
            body "There was no route found between the given addresses"
            return
        else
            distance = body["route_summary"]["total_distance"] / 1000.0

            LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, @distance_id
        end

        result = LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id

        distance
    end

    def distance_by_roads_osrm_first from, to, request_id
        body = distance_by_roads_with_osrm from, to, request_id

        distance = nil # distance in kilometers
        if body["status"] != 200
            # OSRM was not able to route us, so let’s try Google’s thingy instead
            #LocationInterface.sqlite.execute "INSERT INTO distance_calculations (request_id, from_latitude, from_longitude, to_latitude, to_longitude, service_provider) VALUES (?, ?, ?, ?, ?, ?)",
            #        [ request_id, from["latitude"], from["longitude"], to["latitude"], to["longitude"], "google" ]
            #distance_id = LocationInterface.sqlite.last_insert_row_id
            google = Google.new
            distance = google.distance_by_roads to, from
            if distance.nil?
                Airbrake.notify(Notice.new("Google wasn’t able to route us")) do |notice|
                    notice[:params][:response] = response.body
                    notice[:context][:severity] = "error"
                end
                status 404
                body "There was no route found between the given addresses"
                return
            end
            #LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, distance_id
        else
            # first request was ok
            distance = body["route_summary"]["total_distance"] / 1000.0

            #LocationInterface.sqlite.execute "UPDATE distance_calculations SET successful = 1, distance = ? WHERE id = ?", distance, @distance_id
        end

        #result = LocationInterface.sqlite.execute "UPDATE requests SET successful = 1 WHERE id = ?", request_id

        distance
    end

    def distance_by_roads_with_osrm from, to, request_id

        #config = LocationInterface.config
        #LocationInterface.sqlite.execute "INSERT INTO distance_calculations (request_id, from_latitude, from_longitude, to_latitude, to_longitude, service_provider) VALUES (?, ?, ?, ?, ?, ?)",
        #        [ request_id, from["latitude"], from["longitude"], to["latitude"], to["longitude"], config["osrm"]["service_url"] ]
        #@distance_id = LocationInterface.sqlite.last_insert_row_id

        OSRM.distance_by_roads from, to
    end

    run! if app_file == $0
end