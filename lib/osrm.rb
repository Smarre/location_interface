
require "httparty"

# Simple utility for OSRM
class OSRM
    def self.distance_by_roads from, to
        config = LocationInterface.config
        uri = "#{config["osrm"]["service_url"]}/viaroute?loc=#{from["latitude"]}," +
                "#{from["longitude"]}&loc=#{to["latitude"]},#{to["longitude"]}"

        response = HTTParty.get uri
        JSON.parse response.body
    end
end