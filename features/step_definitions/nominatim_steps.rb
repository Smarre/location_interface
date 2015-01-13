
When(/^I geocode given addresses using primary Nominatim interface$/) do
    @responses = []
    @addresses.each do |address|
        result = Address.send :nominatim_query, address
        result = [] if result.nil?
        @responses << { "latitude" => result[0], "longitude" => result[1] }
    end
end

When(/^I geocode given addresses using fallback Nominatim interface$/) do
    @responses = []
    @addresses.each do |address|
        result = Address.send :official_nominatim_query, address
        result = [] if result.nil?
        @responses << { "latitude" => result[0], "longitude" => result[1] }
    end
end
