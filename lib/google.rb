
require "uri"

require "httparty"

require_relative "email"


class Google

    def distance_by_roads from, to
        # distance is distance in kilometers
        distance = search_from_api from, to
        if distance.nil?
            distance = distance_from_print_page from, to
        end

        distance
    end

    private

    # Returns distance in kilometers or nil
    def search_from_api from, to
        result_language = "fi_FI"
        units = "metric"
        origin = "#{from["latitude"]} #{from["longitude"]}"
        destination = "#{to["latitude"]} #{to["longitude"]}"

        url = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=#{URI.escape origin}&destinations=#{URI.escape destination}" +
                "&mode=driving&language=#{URI.escape result_language}&sensor=false&units=#{URI.escape units}"

        response = HTTParty.get url
        begin
            data = JSON.parse response.body
        rescue JSON::ParserError => e
            Email::error_email "Invalid data when trying to do delivery calculation. (1) [#{url}]"
            return nil
        end

        if data["status"].nil?
            Email::error_email "Invalid data received from server. Check the API. (2) [#{url}]"
            return nil
        end

        if data["status"] != "OK"
            Email::error_email "Distance calculation failed for given address information. #{data["status"]} (3) [#{url}]"
            return nil
        end

        # I’m not really sure how to handle error cases here, let’s see this better after we get something that fails
        distance = data["rows"][0]["elements"][0]["distance"]["value"]

        distance / 1000.0
    end

    # returns distance in kilometers or nil
    def search_from_print_page from, to
        return nil # since it’s not allowed to use this page for distance calculation, it’s disabled

        origin = "#{from["latitude"]} #{from["longitude"]}"
        destination = "#{to["latitude"]} #{to["longitude"]}"

        suffix = "f=d&source=s_d&saddr=#{URI.escape origin}&daddr=#{URI.escape destination}&hl=fi&geocode=&mra=ls&ie=UTF8&z=16&pw=2"

        url = "https://maps.google.fi/maps?#{suffix}"

        response = HTTParty.get url

        # TODO: parse response
    end

end