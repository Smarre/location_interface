
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
        if places.count < 1
            return json "No restaurants"
        end

        place = places.each.next

        hash = { latitude: place.lat, longitude: place.lon }
        json hash
    end

    post "/reverse" do
        reverse = Nominatim::Reverse.new
    end

    private

    def parse_config
        contents = Psych.load_file "config/config.yaml"

        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["nominatim"]["service_url"]
            config.search_url = "search.php"
            config.reverse_url = "search.php"
        end
    end

    run! if app_file == $0
end