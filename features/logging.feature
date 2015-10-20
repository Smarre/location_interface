Feature: We have lots of requests going on, but sometimes they don’t go well. We need to know why.

    Scenario: When a request comes it, it will spawn multiple requests to our backends.
    We should track down these requests in order to know what is going wrong.
        Given there is new address "Kauppakaari 1", "04200", "Kerava" and "Kauppakaari 15", "04200", "Kerava"
        When I calculate distance by roads for these two addresses
        Then our logging table should contain entries for Nominatim geocode and OSRM distance calculation
