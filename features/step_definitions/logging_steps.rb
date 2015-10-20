
require "fileutils"

Given(/^there is new address "([^"]*)", "([^"]*)", "([^"]*)" and "([^"]*)", "([^"]*)", "([^"]*)"$/) do |from_address, from_postal_code, from_city, to_address, to_postal_code, to_city|
    @first_address = { "address" => from_address, "postal_code" => from_postal_code, "city" => from_city }
    @second_address = { "address" => to_address, "postal_code" => to_postal_code, "city" => to_city }
    @datetime = DateTime.now.strftime("%Y-%m-%d %H:%M:%S")
end

When(/^I calculate distance by roads for these two addresses$/) do
    options = { body: { from: @first_address, to: @second_address } }
    @response = HTTParty.post("http://localhost:9999/distance_by_roads", options)
    puts @response.body if @response.code != 200
    expect(@response.code).to be(200)
end

Then(/^our logging table should contain entries for Nominatim geocode and OSRM distance calculation$/) do
    sqlite = SQLite3::Database.new "requests.sqlite3"

    rows = sqlite.execute "SELECT id, type, successful, datetime(created_at, 'localtime') AS created_at FROM requests"
    expect(rows.size).to eq(1)

    request_row = rows[0]
    expect(request_row[1]).to eq("distance_by_roads") # type
    expect(request_row[2]).to eq(1) # successful
    expect(request_row[3]).to eq(@datetime) # created_at

    rows = sqlite.execute "SELECT address, postal_code, city, successful, service_provider, datetime(created_at, 'localtime') AS created_at
        FROM geocodes WHERE request_id = ? ORDER BY request_id ASC", request_row[0]
    expect(rows.size).to eq(2)

    row = rows[0] # first address
    expect(row[0]).to eq(@first_address["address"]) # address
    expect(row[1]).to eq(@first_address["postal_code"]) # postal_code
    expect(row[2]).to eq(@first_address["city"]) # city
    expect(row[3]).to eq(1) # successful
    expect(row[4]).to eq("http://nominatim.slm.fi/") # service_provider
    expect(row[5]).to eq(@datetime) # created_at
    row = rows[1] # second address
    expect(row[0]).to eq(@second_address["address"]) # address
    expect(row[1]).to eq(@second_address["postal_code"]) # postal_code
    expect(row[2]).to eq(@second_address["city"]) # city
    expect(row[3]).to eq(1) # successful
    expect(row[4]).to eq("http://nominatim.slm.fi/") # service_provider
    expect(row[5]).to eq(@datetime) # created_at

    rows = sqlite.execute "SELECT from_latitude, from_longitude, to_latitude, to_longitude, distance, successful, service_provider, datetime(created_at, 'localtime') AS created_at
        FROM distance_calculations WHERE request_id = ? ORDER BY request_id ASC", request_row[0]
    expect(rows.size).to eq(1)

    row = rows[0] # first address
    # Not bothering to be too strict about coordinates here
    expect(row[0]).to be_within(0.0001).of(60.4025595) # from_latitude
    expect(row[1]).to be_within(0.0001).of(25.1031777) # from_longitude
    expect(row[2]).to be_within(0.0001).of(60.4038035) # to_latitude
    expect(row[3]).to be_within(0.0001).of(25.0991122) # to_longitude
    expect(row[4]).to be_within(0.01).of(0.778) # distance
    expect(row[5]).to eq(1) # successful
    expect(row[6]).to eq("http://location.slm.fi:5000") # service_provider
    expect(row[7]).to eq(@datetime) # created_at
end

