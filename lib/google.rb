
require "uri"

require "httparty"
require "nokogiri"

class Google

    # Returns latitude, longitude or nil in case of error
    def geocode address_string
        return nil if LocationInterface.config["google"]["geocode"]["api_key"].nil? or LocationInterface.config["google"]["geocode"]["api_key"].empty?
        api_key = LocationInterface.config["google"]["geocode"]["api_key"]
        url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{URI.escape address_string}&components=country:FI&language=fi&region=fi&key=#{api_key}"

        response = HTTParty.get url
        data = JSON.parse response.body
        if not data["status"] == "OK"
            Airbrake.notify(Notice.new("Invalid response from Google’s geocode api with url")) do |notice|
                notice[:params][:address_string] = address_string
                notice[:params][:url] = url
                notice[:context][:severity] = "warning"
            end
            return nil
        end

        # we can’t trust approximate matches, they can be anything
        return nil if data["results"][0]["geometry"]["location_type"] == "APPROXIMATE"

        latitude = data["results"][0]["geometry"]["location"]["lat"]
        longitude = data["results"][0]["geometry"]["location"]["lng"]

        return latitude, longitude
    end

    # Returns latitude, longitude or nil in case of error
    def reverse latitude, longitude
        return nil if LocationInterface.config["google"]["geocode"]["api_key"].nil? or LocationInterface.config["google"]["geocode"]["api_key"].empty?
        api_key = LocationInterface.config["google"]["geocode"]["api_key"]
        url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{latitude},#{longitude}&key=#{api_key}"

        response = HTTParty.get url
        data = JSON.parse response.body
        if not data["status"] == "OK"
            Airbrake.notify(Notice.new("Invalid response from Google’s reverse api with url")) do |notice|
                notice[:params][:latitude] = latitude
                notice[:params][:longitude] = longitude
                notice[:params][:url] = url
                notice[:context][:severity] = "warning"
            end
            return nil
        end

        components = data["results"][0]["address_components"]
        street_address = nil
        street_number = nil
        city = nil
        postal_code = nil

        components.each do |component|
            street_number   = component["long_name"] if component["types"].include? "street_number"
            street_address  = component["long_name"] if component["types"].include? "route"
            postal_code     = component["long_name"] if component["types"].include? "postal_code"
            city            = component["long_name"] if component["types"].include? "administrative_area_level_3"
            city            = component["long_name"] if component["types"].include? "locality"
        end

        {
            "address" => "#{street_address} #{street_number}",
            "city" => city,
            "postal_code" => postal_code
        }
    end

    def distance_by_roads from, to
        # distance is distance in kilometers
        distance = search_from_api from, to

        distance
    end

    private

    # Takes arrays that contains latitude and longitude as arguments
    # Returns distance in kilometers or nil
    def search_from_api from, to
        result_language = "fi_FI"
        units = "metric"
        origin = "#{from["latitude"]} #{from["longitude"]}"
        destination = "#{to["latitude"]} #{to["longitude"]}"

        return nil if LocationInterface.config["google"]["geocode"]["api_key"].nil? or LocationInterface.config["google"]["geocode"]["api_key"].empty?
        api_key = LocationInterface.config["google"]["geocode"]["api_key"]

        url = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=#{URI.escape origin}&destinations=#{URI.escape destination}" +
                "&mode=driving&language=#{URI.escape result_language}&sensor=false&units=#{URI.escape units}&key=#{api_key}"

        response = HTTParty.get url
        begin
            data = JSON.parse response.body
        rescue JSON::ParserError => e
            Airbrake.notify(Notice.new("Invalid data when trying to do delivery calculation")) do |notice|
                notice[:params][:from] = from
                notice[:params][:to] = to
                notice[:params][:url] = url
                notice[:context][:severity] = "warning"
            end
            return nil
        end

        if data["status"].nil?
            Airbrake.notify(Notice.new("Invalid data received from server. Check the API.")) do |notice|
                notice[:params][:from] = from
                notice[:params][:to] = to
                notice[:params][:url] = url
                notice[:params][:data] = data
                notice[:context][:severity] = "warning"
            end
            return nil
        end

        if data["status"] != "OK" || data["rows"][0]["elements"][0]["status"] != "OK"
            Airbrake.notify(Notice.new("Distance calculation failed for given address information.")) do |notice|
                notice[:params][:from] = from
                notice[:params][:to] = to
                notice[:params][:url] = url
                notice[:params][:data] = data
                notice[:context][:severity] = "warning"
            end
            return nil
        end

        distance = data["rows"][0]["elements"][0]["distance"]["value"]

        distance / 1000.0
    end
end
