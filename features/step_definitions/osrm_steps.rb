
Given(/^there in following addresses to route from:$/) do |table|
    @from_addresses = []
    table.hashes.each do |address|
        lat, lon = Address.send(:nominatim_query, address)
        #puts "#{lat} #{lon}"
        if address["address"] == "Majavatie 9" and address["city"] == "Vantaa"
            expect(lat).to be_nil
            expect(lon).to be_nil
        else
            expect(lat).not_to be_nil
            expect(lon).not_to be_nil
        end
        @from_addresses << { "latitude" => lat, "longitude" => lon }
    end
end

Given(/^there in following addresses to route to:$/) do |table|
    @to_addresses = []
    table.hashes.each do |address|
        lat, lon = Address.send(:nominatim_query, address)
        #puts "#{lat} #{lon}"
        expect(lat).not_to be_nil
        expect(lon).not_to be_nil
        @to_addresses << { "latitude" => lat, "longitude" => lon }
    end
end


When(/^I calculate route between these two addresses using OSRM$/) do
    @responses = []
    @from_addresses.each_with_index do |address, index|
        body = LocationInterface.send(:distance_by_roads_with_osrm, address, @to_addresses[index])
        if body["route_summary"].nil?
            @responses << nil
            next
        end
        @responses << body["route_summary"]["total_distance"] / 1000.0
    end
end

Then(/^distance between these addresses should be following kilometers:$/) do |kilometers_table|
    kilometers = kilometers_table.raw[0]

    kilometers.each_with_index do |km, index|
        expect(@responses[index]).to eq(km.to_f)
    end
end
