Feature: geocoding using the interface
    We have nice /geocode method, and we want to use it!

    Scenario: Someone forgot its own address and hence needs to convert city name to coordinates
        Given there is a customer with unknown address, but from city "Kerava"
        When converting the city to coordinates
        Then resulting coordinates should be "60.4000005" and "25.1166696"
