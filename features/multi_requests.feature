Feature: Sometimes we have more than one address to query.

    Scenario: we have list of addresses between A and B and we want to get distance by roads between them.
        Given there in following addresses to route from:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04250       |
            | Hakopolku 2             | Vantaa | 01360       |
            | Husbackankuja 4         | Vantaa | 01610       |
            # Majavatie won’t work as we hardcode the address coordinates to Nominatim which does not return a result.
            # In real environment it will work.
            #| Majavatie 9             | Vantaa | 20540       |
        And there in following addresses to route to:
            | address                 | city         | postal_code |
            | Linjatie 1              | Lapinlahti   | 73201       |
            | Hiekkaharjuntie 18      | Vantaa       | 01350       |
            | Liesitori 1             | Vantaa       | 01600       |
            #| Maakotkantie 6          | Vantaa       | 01450       |
        When I calculate route between these two addresses using multi distance by roads
        Then distance between these addresses should be following kilometers:
            | 420.899 |
            | 4.062   |
            | 2.19    |
            #| 1.702   |

    Scenario: we have list of addresses which for we need coordinates. We should do it in efficient way.
        Given there is following address:
            | address                 | city     | postal_code |
            | Lintulammenkatu 13      | Kerava   | 04250       |
            | Jokiniementie 4         | Helsinki | 00650       |
            | Majavatie 9             | Vantaa   |             |
            | Majavatie 9             | Helsinki |             |
        When I geocode given addresses using multi geocode
        Then resulting coordinates should be:
            | latitude    | longitude        |
            | 60.3961232  | 25.1070479277008 |
            | 60.2243508  | 24.9724909582648 |
            | 60.3506502  | 25.0925598       |
            | 60.20348285 | 25.0300153903916 |