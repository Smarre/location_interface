
require "httparty"
require "ostruct"

# TODO: test for latitude and longitude routing

Given(/^there is following coordinates:$/) do |table|
    @coordinates = table.hashes
end

Given(/^there is following address:$/) do |table|
    @addresses = table.hashes
end

Given(/^there in following address to route from:$/) do |table|
    @from_address = table.hashes[0]
end

Given(/^there in following address to route to:$/) do |table|
    @to_address = table.hashes[0]
end

When(/^I calculate route between these two addresses$/) do
    options = { body: { from: @from_address, to: @to_address } }
    @response = HTTParty.post("http://localhost:9999/distance_by_roads", options)
    puts @response.body if @response.code != 200
    expect(@response.code).to be(200)
end

When(/^I geocode given addresses$/) do
    @responses = []
    @addresses.each do |address_hash|
        options = { body: {
                           address: address_hash["address"],
                           postal_code: address_hash["postal_code"],
                           city: address_hash["city"]
                          }
                  }
        response = HTTParty.post("http://localhost:9999/geocode", options)
        #puts response.body if response.code != 200
        expect(response.code).to be(200)
        @responses << response
    end

    @responses.map! do |response|
        JSON.parse response.body
    end
end

When(/^I reverse geocode given coordinates$/) do
    @responses = []
    @coordinates.each do |coordinate_hash|
        options = { body: coordinate_hash }
        response = HTTParty.post("http://localhost:9999/reverse", options)
        #puts response.body #if response.code != 200
        expect(response.code).to eq(200)
        @responses << response
    end

    @responses.map! do |response|
        JSON.parse response.body
    end
end

Then(/^distance between these addresses should be (\d+.\d+) kilometers$/) do |km_amount|
    total_distance = @response.body
    expect(total_distance).to eq(km_amount)
end

Then(/^resulting coordinates should be:$/) do |table|
    data = table.hashes

    data.each_with_index do |coordinates, index|
        coordinates = { "latitude" => coordinates["latitude"].to_f, "longitude" => coordinates["longitude"].to_f }
        coordinates = { "latitude" => nil, "longitude" => nil } if coordinates["latitude"] == 0.0
        response = @responses[index]

        expect(response).to eq(coordinates)
    end
end

Then(/^resulting address should be:$/) do |table|
    data = table.hashes

    data.each_with_index do |address, index|
        #address = { "address" => coordinates["latitude"].to_f, "longitude" => coordinates["longitude"].to_f }
        response = @responses[index]

        expect(response).to eq(address)
    end
end

