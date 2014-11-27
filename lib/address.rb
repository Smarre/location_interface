
class Address

    # Splits street address and returns hash of street address, street number and house number
    def self.split_street street
        street_name = nil
        street_number = nil
        house_number = nil

        street.gsub! /,/, ""
        splitted = street.split " "
        street_name = splitted[0]

        unless splitted[1].nil?
            street_number = splitted[1]
        end

        unless splitted[2].nil?
            splitted.delete_at 0
            splitted.delete_at 0
            house_number = splitted.join " "
        end

        {
            street_name: street_name,
            street_number: street_number,
            house_number: house_number
        }
    end

end