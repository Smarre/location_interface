
require "httparty"

Given(/^there is following address:$/) do |table|
    @addresses = table.hashes
end

When(/^I geocode given addresses$/) do
    @responses = []
    @addresses.each do |address_hash|
        address_string = "#{address_hash["address"]}, #{address_hash["postal_code"]} #{address_hash["city"]}"
        options = { body: { address_string: address_string } }
        response = HTTParty.post("http://localhost:9999/geocode", options)
        expect(response.code).to be(200)
        @responses << response
    end
end

Then(/^resulting coordinates should be:$/) do |table|
    data = table.hashes

    data.each_with_index do |coordinates, index|
        coordinates = { "latitude" => coordinates["latitude"].to_f, "longitude" => coordinates["longitude"].to_f }
        response = @responses[index]

        expect(JSON.parse(response.body)).to eq(coordinates)
    end
end
