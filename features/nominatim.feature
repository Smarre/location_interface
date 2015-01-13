Feature: Geocoding with Nominatim
    Since we use Nominatim for geocoding tasks, we need to ensure it works as expected.
    For that, we need to test that all features we use for it works and returns the values they are expected to,
    and that fallbacks don’t kick in when they shouldn’t.

    Scenario: test that address returns expected coordinates
        Given there is following address:
            | address                 | city     | postal_code |
            | Lintulammenkatu 13      | Kerava   | 04250       |
            | Jokiniementie 4         | Helsinki | 00650       |
            | Jokiniementie 4         | Helsinki |             |
            | Majavatie 9             | Vantaa   |             |
            | Majavatie 9             | Helsinki |             |
        When I geocode given addresses using primary Nominatim interface
        Then resulting coordinates should be:
            | latitude    | longitude        |
            | 60.3961232  | 25.1070479277008 |
            |             |                  |
            | 60.2243508  | 24.9724909582648 |
            |             |                  |
            | 60.20348285 | 25.0300153903916 |

    # This scenario won’t work, as it tests the fallback Nominatim, which we the tests can’t otherwise use.
    # To run this test, set fallback_nominatim on config.yaml and then run only this test.
    @fallback_nominatim
    Scenario: test that the coordinates works with fallback Nominatim too
        Given there is following address:
            | address                 | city     | postal_code |
            | Lintulammenkatu 13      | Kerava   | 04250       |
            | Jokiniementie 4 B 11    | Helsinki | 00650       |
            | Jokiniementie 4 B 11    | Helsinki |             |
        When I geocode given addresses using fallback Nominatim interface
        Then resulting coordinates should be:
            | latitude    | longitude        |
            | 60.3961232  | 25.1070479277008 |
            |             |                  |
            | 60.2258919  | 24.9732973 |