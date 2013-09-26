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
            | 60.3961465 | 25.107054513076 |

    Scenario: convert coordinates to address
        Given there is following coordinates:
            | latitude   | longitude       |
            | 60.3961465 | 25.107054513076 |
        When I reverse geocode given coordinates
        Then resulting address should be:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04200       |