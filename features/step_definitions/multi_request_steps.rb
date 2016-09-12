
When(/^I geocode given addresses using multi geocode$/) do
    options = {
        body: {
            "addresses" => {}
        }
    }

    @addresses.each_with_index do |address, index|
        options[:body]["addresses"][index] = address
    end

    response = HTTParty.post("http://localhost:9999/multi_geocode", options)
    #puts response.body if response.code != 200
    expect(response.code).to be(200)
    @responses = JSON.parse response.body

    # Converting to array so the existing validator can do the job
    @responses = @responses.values
    puts @responses.inspect
end

When(/^I calculate route between these two addresses using multi distance by roads$/) do
    options = { body: { "addresses" => {} } }

    @from_addresses.each_with_index do |value, index|
        options[:body]["addresses"][index] = { "from" => @from_addresses[index], "to" => @to_addresses[index] }
    end

    response = HTTParty.post("http://localhost:9999/multi_distance_by_roads", options)
    #puts response.body if response.code != 200
    expect(response.code).to be(200)
    @responses = JSON.parse response.body
    @responses = @responses.values
end
