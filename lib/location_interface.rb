
require "sinatra"
require "sinatra/json"
require "nominatim"
require "psych"

class LocationInterface < Sinatra::Base

    helpers Sinatra::JSON

    before do
        parse_config
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

        return "nya"
        return json params
        result = Nominatim.reverse(params["latitude"], params["longitude"]).address_details(true).fetch

        return json "Nothing found for given coordinates" if result.nil?

        result.address.city
        #"nya"
        #result
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
end