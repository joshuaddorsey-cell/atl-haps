# Dirty South venue reference provenance

Verified October 1, 2026. The live organizer homepage supplies weekday, venue, neighborhood, clock time and show type. The user confirmed all listed clock times are PM. No event schedule is bundled: removing a show from the homepage removes it on the next successful refresh. Reference addresses in `lib/dirty_venues.dart` are matched by venue AND neighborhood, so multi-location businesses stay separate. All 33 addresses were matched by the US Census Public_AR_Current geocoder to the same postal codes. The returned address-range coordinates are approximate and now support Near me. Raw matches and request URLs are in `dirty-south-geocoding.json`. Schedules still refresh live. Bona Fide (1454 La France St NE) and Limerick Junction (822 N Highland Ave NE) were also matched to their respective Atlanta addresses.

Official address sources:

- [Grindhouse locations](https://www.grindhouseburgers.com/): all five scheduled branches.
- [McCray's locations](https://www.mccraystavern.com/locations): Beltline, Midtown, Smyrna.
- [Wild Heaven contact](https://wildheavenbeer.com/contact): Avondale, West End, Toco Hills.
- [Amasa](https://www.amasamexican.com/): 15 Academy Street, Space 1E.
- [Ormsby's](https://www.ormsbysatlanta.com/contact), [Parkgrounds](https://www.parkgroundsatl.com/about), [Punch Bowl Social](https://punchbowlsocial.com/location/atlanta).
- [Close Company](https://www.closecompanybar.com/): Atlanta branch; ignore homepage's incorrect shared Breaker Breaker link.
- [Fado Midtown](https://www.fadoirishpub.com/atlanta-midtown), [Monday Night locations](https://mondaynightbrewing.com/contact/): West Midtown and Garage.
- [Savage Pizza](https://savagepizza.com/savage-pizza-locations): Norcross branch.
- [Blue Moon](https://www.bluemoonbreweryandgrill.com/visit/), [Bone Garden](https://www.bonegardencantina.com/), [Little 5 Pub](https://little5pub.com/), [Monks](https://monksmeadery.com/pages/contact).
- Dirty South organizer venue pages: [Hotel Clermont](https://www.dirtysouthtrivia.com/hotelclermont), [Chicheria](https://www.dirtysouthtrivia.com/chicheria), [Sceptre](https://www.dirtysouthtrivia.com/sceptrebrewing), [Breaker Breaker](https://www.dirtysouthtrivia.com/breakerbreaker), [Fado Buckhead](https://www.dirtysouthtrivia.com/fado-buckhead), [Industry Tavern](https://www.dirtysouthtrivia.com/industry-tavern), [Round Trip Underwood Hills](https://www.dirtysouthtrivia.com/round-trip-brewing), [Round Trip East Cobb](https://www.dirtysouthtrivia.com/round-trip-brewing-ec), [Family Dog](https://www.dirtysouthtrivia.com/the-family-dog).

Bona Fide's three shows are covered by the direct venue feed, avoiding duplicate Dirty South listings. New, unrecognized venues retain their published neighborhood and an explicit street-address confirmation note until verified. End times are not invented.
