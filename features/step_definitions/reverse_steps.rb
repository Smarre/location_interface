
Given(/^there is a customer with latitude (\d+\.\d+) and longitude (\d+\.\d+)$/) do |latitude, longitude|
    @latitude = latitude
    @longitude = longitude
end

When(/^converting the coordinates to an address$/) do
    post "/reverse", { "latitude" => @latitude, "longitude" => @longitude }
end

Then(/^resulting address should be "([^"]*)", city should be "([^"]*)" and postal code should be "([^"]*)"$/) do |address, city, postal_code|
    data = JSON.parse last_response.body
    expect(data["address"]).to eq(address)
    expect(data["city"]).to eq(city)
    expect(data["postal_code"]).to eq(postal_code)
end
