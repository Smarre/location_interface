
require "uri"

require_relative "email"
require_relative "google"

class Address

    @@logger = Logger.new "log/loggy.log", "daily"
    @@sqlite = nil

    # Splits street address and returns hash of street address, street number and house number
    def self.split_street street
        street_name = nil
        street_number = nil
        house_number = nil

        street.gsub! /,/, ""
        splitted = street.split " "
        iter = splitted.dup.each
        street_name = iter.next
        splitted.delete_at 0

        begin
        loop do
            part = iter.next
            if part[0] =~ /[[:digit:]]/
                street_number = part
                splitted.delete_at 0
                break
            end
            street_name += " #{part}"
            splitted.delete_at 0
        end
        rescue StopIteration => e
            # all fine
        end

        house_number = splitted.join " "

        {
            street_name: street_name,
            street_number: street_number,
            house_number: house_number
        }
    end

    def self.address_to_coordinates address
        latitude = nil
        longitude = nil

        split_address = self.split_street(address["address"])
        street_address = "#{split_address[:street_name]} #{split_address[:street_number]}"
        address_with_postal_code_string = "#{street_address}, #{address["postal_code"]} #{address["city"]}"
        unless address["city"].empty?
            address_string = "#{street_address}, #{address["city"]}"
        else
            address_string = "#{street_address}, #{address["postal_code"]}"
        end
        lat, lon = self.nominatim_query address_with_postal_code_string
        return lat, lon unless lat.nil?

        # didn’t get results, let’s try without postal code then
        lat, lon = self.nominatim_query address_string
        return lat, lon unless lat.nil?

        # let’s try OSM’s Nominatim service if it gives better results to us
        lat, lon = self.official_nominatim_query address_with_postal_code_string
        return lat, lon unless lat.nil?

        # didn’t get results, let’s try without postal code then
        lat, lon = self.official_nominatim_query address_string
        return lat, lon unless lat.nil?

        # If even that failed, let’s still try with Google
        google = Google.new
        latitude, longitude = google.geocode address_string
        return latitude, longitude if not latitude.nil?

        status 404
        body "No coordinates found for given address"
        nil
    end

    def self.official_nominatim_query address_string, featuretype = nil
        contents = Psych.load_file "config/config.yaml"
        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = "http://nominatim.openstreetmap.org"
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
        end
        lat, lon = self.nominatim_query address_string, featuretype
        LocationInterface.configure_nominatim

        if not lat.nil?
            Email.error_email "For some reason official Nominatim returned results but ours didn’t, for address #{address_string}"
            return lat, lon
        end
        nil
    end

    def self.nominatim_query address_string, featuretype = nil
        sqlite.execute "INSERT INTO loggy (service, url) VALUES (?, ?)", [ "nominatim address_to_coordinates", address_string ]
        places = Nominatim.search(address_string).limit(1).address_details(true).featuretype("city")
        #if not featuretype.nil?
            places.featuretype(featuretype)
        #end
        #@@logger.info address_string
        place = places.first
        return place.lat, place.lon if places.count > 0
        nil
    end


    # TODO: this is dupe from LocationInterface
    def self.sqlite
        return @@sqlite if not @@sqlite.nil?

        @@sqlite = SQLite3::Database.new "requests.sqlite3"
        @@sqlite.execute <<-SQL
        create table if not exists loggy (
            service varchar(50),
            url varchar(100)
        );
        SQL

        @@sqlite
    end

end