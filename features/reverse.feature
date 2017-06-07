Feature: reverse geocoding using the interface
    We have nice /reverse method, and we want to use it!

    Scenario Outline: Someone forgot its own address and wants to convert coordinates she remembers into an address
        Given there is a customer with latitude <latitude> and longitude <longitude>
        When converting the coordinates to an address
        Then resulting address should be "<address>", city should be "<city>" and postal code should be "<postal code>"

        Examples:
           | latitude   | longitude     | address         | city          | postal code   |
           | 60.99782   | 24.45521      | Kaivokatu 22    | Hämeenlinna   | 13130         |
           | 60.9987415 | 24.454270105  | Kaivokatu 24    | Hämeenlinna   | 13100         |