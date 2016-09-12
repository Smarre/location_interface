Feature: Since we have a feature of calculating distance by roads, we should get successful
results by using OSRM to do the routing for us.

    Scenario: we have pair of addresses we want to calculate distance by roads between them
        Given there in following addresses to route from:
            | address                 | city   | postal_code |
            | Lintulammenkatu 13      | Kerava | 04250       |
            # customer lives in an apartment, so there is extraneous components in an address
            | Hakopolku 2             | Vantaa | 01360       |
            | Husbackankuja 4         | Vantaa | 01610       |
            # when querying coordinates for address in Vantaa, we don’t want coordinates for Majavatie in Helsinki, as we used to
            | Majavatie 9             | Vantaa | 20540       |
        And there in following addresses to route to:
            | address                 | city         | postal_code |
            | Linjatie 1              | Lapinlahti   | 73201       |
            | Hiekkaharjuntie 18      | Vantaa       | 01350       |
            | Liesitori 1             | Vantaa       | 01600       |
            | Maakotkantie 6          | Vantaa       | 01450       |
        When I calculate route between these two addresses using OSRM
        Then distance between these addresses should be following kilometers:
            | 420.899 |
            | 4.062   |
            | 2.19    |
            | 1.702   |

            # TODO: test with coordinates, instead of converting address