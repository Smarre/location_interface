
require "uri"

require_relative "google"

class Address

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

    def self.address_to_coordinates input_address, request_id
        latitude = nil
        longitude = nil

        #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
        #            [ request_id, input_address["address"], input_address["postal_code"], input_address["city"], LocationInterface.config["nominatim"]["service_url"] ]
        #geocode_id = LocationInterface.sqlite.last_insert_row_id
        geocode_id = 0

        address = input_address.dup

        split_address = self.split_street(address["address"])
        street_address = "#{split_address[:street_name]} #{split_address[:street_number]}"
        address["address"] = street_address

        nominatim_first input_address, address, geocode_id, request_id
        #google_first input_address, address, geocode_id, request_id
    end

    private

    def self.google_first input_address, address, geocode_id, request_id
        google = Google.new
        LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
                    [ request_id, address["address"], address["postal_code"], address["city"], "google" ]
        geocode_id = LocationInterface.sqlite.last_insert_row_id
        address_string = "#{address["address"]}, #{address["city"]}"
        latitude, longitude = google.geocode address_string
        if not latitude.nil?
            LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return latitude, longitude
        end

        # didn’t get results, let’s try with Nominatim then
        lat, lon = self.nominatim_query address, "default"
        unless lat.nil?
            LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return lat, lon
        end

        # didn’t get results, let’s try without postal code then
        address["postal_code"] = nil
        LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
                    [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["nominatim"]["service_url"] ]
        geocode_id = LocationInterface.sqlite.last_insert_row_id
        lat, lon = self.nominatim_query address, "default without postal code"
        unless lat.nil?
            LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return lat, lon
        end
        address["postal_code"] = input_address["postal_code"]

        # didn’t get results, let’s try with postal code and without city then
        unless input_address["postal_code"].nil?
            address["city"] = nil
            LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
                    [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["nominatim"]["service_url"] ]
            geocode_id = LocationInterface.sqlite.last_insert_row_id
            lat, lon = self.nominatim_query address, "default without city"
            unless lat.nil?
                LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
                return lat, lon
            end

            address["city"] = input_address["city"]
        end

        nil
    end

    def self.nominatim_first input_address, address, geocode_id, request_id
        lat, lon = self.nominatim_query address, "default"
        unless lat.nil?
            #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return lat, lon
        end

        # didn’t get results, let’s try without postal code then
        address["postal_code"] = nil
        #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
        #            [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["nominatim"]["service_url"] ]
        #geocode_id = LocationInterface.sqlite.last_insert_row_id
        lat, lon = self.nominatim_query address, "default without postal code"
        unless lat.nil?
            #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return lat, lon
        end
        address["postal_code"] = input_address["postal_code"]

        # didn’t get results, let’s try with postal code and without city then
        unless input_address["postal_code"].nil?
            address["city"] = nil
            #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
            #        [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["nominatim"]["service_url"] ]
            #geocode_id = LocationInterface.sqlite.last_insert_row_id
            lat, lon = self.nominatim_query address, "default without city"
            unless lat.nil?
                #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
                return lat, lon
            end

            address["city"] = input_address["city"]
        end

        contents = Psych.load_file "config/config.yaml"
        unless contents["fallback_nominatim"].nil?
            # let’s try fallback Nominatim service if it gives better results to us
            #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
            #        [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["fallback_nominatim"] ]
            #geocode_id = LocationInterface.sqlite.last_insert_row_id
            lat, lon = self.official_nominatim_query address
            unless lat.nil?
                #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
                return lat, lon
            end

            # didn’t get results, let’s try without postal code then
            address["postal_code"] = nil
            #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
            #        [ request_id, address["address"], address["postal_code"], address["city"], LocationInterface.config["fallback_nominatim"] ]
            #geocode_id = LocationInterface.sqlite.last_insert_row_id
            lat, lon = self.official_nominatim_query address, "without postal code"
            unless lat.nil?
                #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
                return lat, lon
            end
        end

        # If even that failed, let’s still try with Google
        google = Google.new
        #LocationInterface.sqlite.execute "INSERT INTO geocodes (request_id, address, postal_code, city, service_provider) VALUES (?, ?, ?, ?, ?)",
        #            [ request_id, address["address"], address["postal_code"], address["city"], "google" ]
        #geocode_id = LocationInterface.sqlite.last_insert_row_id
        address_string = "#{address["address"]}, #{address["city"]}"
        latitude, longitude = google.geocode address_string
        if not latitude.nil?
            #LocationInterface.sqlite.execute "UPDATE geocodes SET successful = 1 WHERE id = ?", geocode_id
            return latitude, longitude
        end

        nil
    end

    def self.official_nominatim_query address, log_string = "", featuretype = nil
        contents = Psych.load_file "config/config.yaml"
        return nil if contents["fallback_nominatim"].nil?
        Nominatim.configure do |config|
            config.email = contents["nominatim"]["email"]
            config.endpoint = contents["fallback_nominatim"]
            config.search_url = "search.php"
            config.reverse_url = "reverse.php"
            if (not contents["fallback_nominatim_api_key"].nil?) or (not contents["fallback_nominatim_api_key"].empty?)
                config.key = contents["fallback_nominatim_api_key"]
            end
        end
        lat, lon = self.nominatim_query address, "fallback #{log_string}", featuretype
        LocationInterface.configure_nominatim

        if not lat.nil?
            Airbrake.notify(Notice.new("For some reason official Nominatim returned results but ours didn’t")) do |notice|
                notice[:params][:address] = address
                notice[:context][:severity] = "notice"
            end
            return lat, lon
        end
        nil
    end

    def self.nominatim_query address, log_string = "", featuretype = nil
        address = address.dup
        places = Nominatim.search.street(address["address"]).city(address["city"]).postalcode(address["postal_code"])
        places.limit(1).address_details(true)
        places.featuretype(featuretype)
        begin
            place = places.first
        rescue MultiJson::ParseError => e
            Airbrake.notify e
            return nil
        end

        return place.lat, place.lon if places.count > 0
        nil
    end

end