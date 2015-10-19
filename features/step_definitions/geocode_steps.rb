
require "httparty"

Given(/^there is a customer with unknown address, but from city "(.*?)"$/) do |city|
    @city = city
end

When(/^converting the city to coordinates$/) do
    options = { body: { city: @city } }
    @response = HTTParty.post("http://localhost:9999/geocode", options)
    puts @response.body if @response.code != 200
    expect(@response.code).to be(200)
end

Then(/^resulting coordinates should be "(.*?)" and "(.*?)"$/) do |latitude, longitude|
    body = JSON.parse @response.body
    expect(body["latitude"]).to be(latitude.to_f)
    expect(body["longitude"]).to be(longitude.to_f)
end

