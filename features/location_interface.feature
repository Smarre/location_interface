Feature: Location
    When someone wants to locate something, or calculate distance between two points,
    or something similar related to coordinates, a good location interface is a must.

    Scenario: convert address to coordinates
        Given there is following address:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04250       |
        When I geocode given addresses
        Then resulting coordinates should be:
            | latitude   | longitude       |
            | 60.39616065 | 25.1070625157963 |

    Scenario: convert coordinates to address
        Given there is following coordinates:
            | latitude   | longitude       |
            | 60.3961465 | 25.107054513076 |
        When I reverse geocode given coordinates
        Then resulting address should be:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04200       |

    Scenario: there is an address we want a route for
        Given there in following address to route from:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04250       |
        And there in following address to route to:
            | address                 | city         | postal_code |
            | Linjatie 1              | Varpaisjärvi | 73200       |
        When I calculate route between these two addresses
        Then distance between these addresses should be 420.856 kilometers

    Scenario: customer lives in an apartment, so there is extraneous components in an address
        Given there in following address to route from:
            | address                 | city   | postal_code |
            | Hakopolku 2             | Vantaa | 01360       |
        And there in following address to route to:
            | address                 | city   | postal_code |
            | Hiekkaharjuntie 18 A 1  | Vantaa | 01300       |
        When I calculate route between these two addresses
        Then distance between these addresses should be 3.77 kilometers

    Scenario: also hustbacka addresses needs to work
        Given there in following address to route from:
            | address                 | city   | postal_code |
            | Husbackankuja 4 b 41    | Vantaa | 01610       |
        And there in following address to route to:
            | address                 | city   | postal_code |
            | Liesitori 1             | Vantaa | 01600       |
        When I calculate route between these two addresses
        Then distance between these addresses should be 2.231 kilometers