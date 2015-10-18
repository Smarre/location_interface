
require "uri"

require_relative "email"
require_relative "google"

class Address

    @@logger = Logger.new "log/loggy.log", "daily"
    @@sqlite = nil

    # Splits street address and returns hash of street address, street number and house number
    #
    # Returns nil in case of street.nil?
    def self.split_street street

        street_name = nil
        street_number = nil
        house_number = nil

        catch(:end) do
            throw :end if street.nil?
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
        end

        {
            street_name: street_name,
            street_number: street_number,
            house_number: house_number
        }
    end

    def self.address_to_coordinates input_address
        latitude = nil
        longitude = nil

        address = input_address

        split_address = self.split_street(address["address"])
        street_address = "#{split_address[:street_name]} #{split_address[:street_number]}"
        address["address"] = street_address

        lat, lon = self.nominatim_query address, "default"
        return lat, lon unless lat.nil?

        # didn’t get results, let’s try without postal code then
        address["postal_code"] = nil
        lat, lon = self.nominatim_query address, "default without postal code"
        return lat, lon unless lat.nil?

        # didn’t get results, let’s try with postal code and without city then
        unless address["postal_code"].nil?
            #@@logger.info input_address["postal_code"].inspect
            address["postal_code"] = input_address["postal_code"]
            address["city"] = nil
            lat, lon = self.nominatim_query address, "default without city"
            return lat, lon unless lat.nil?
        end

        contents = Psych.load_file "config/config.yaml"
        unless contents["fallback_nominatim"].nil?
            # let’s try fallback Nominatim service if it gives better results to us
            address["city"] = input_address["city"]
            lat, lon = self.official_nominatim_query address
            return lat, lon unless lat.nil?

            # didn’t get results, let’s try without postal code then
            address["postal_code"] = nil
            lat, lon = self.official_nominatim_query address, "without postal code"
            return lat, lon unless lat.nil?
        end

        # If even that failed, let’s still try with Google
        google = Google.new
        address_string = "#{address["address"]}, #{address["city"]}"
        latitude, longitude = google.geocode address_string
        return latitude, longitude if not latitude.nil?

        nil
    end

    private

    def self.official_nominatim_query address, log_string = "", featuretype = nil
        contents = Psych.load_file "config/config.yaml"
        return nil if contents["fallback_nominatim"].nil?
        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["fallback_nominatim"]
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
            config.api_key = contents["fallback_nominatim_api_key"] unless contents["fallback_nominatim_api_key"].nil? or !contents["fallback_nominatim_api_key"].empty?
        end
        lat, lon = self.nominatim_query address, "fallback #{log_string}", featuretype
        LocationInterface.configure_nominatim

        if not lat.nil?
            Email.error_email "For some reason official Nominatim returned results but ours didn’t, for address #{address}"
            return lat, lon
        end
        nil
    end

    def self.nominatim_query address, log_string = "", featuretype = nil
        sqlite.execute "INSERT INTO loggy (service, url) VALUES (?, ?)", [ "nominatim #{log_string} address_to_coordinates", address.to_s ]
        places = Nominatim.search.street(address["address"]).city(address["city"]).postalcode(address["postal_code"])
        places.limit(1).address_details(true)
        places.featuretype(featuretype)
        #@@logger.info address.inspect
        begin
            place = places.first
        rescue MultiJson::ParseError => e
            # This means that we were not able to get proper answer from the service, so let’s send an error email.
            Email.error_email "The nominatim thingy sent invalid response to us: #{e}"
            return nil
        end

        return place.lat, place.lon if places.count > 0
        nil
    end

    def self.sqlite
        LocationInterface.send :sqlite
    end

end