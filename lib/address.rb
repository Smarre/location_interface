
class Address

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

        iter.each do |part|
            if part[0] =~ /[[:digit:]]/
                street_number = part
                splitted.delete_at 0
                break
            end
            street_name += " #{part}"
            splitted.delete_at 0
        end

        house_number = splitted.join " "

        {
            street_name: street_name,
            street_number: street_number,
            house_number: house_number
        }
    end

end