// Venue reference addresses verified 2026-10-01; schedules are fetched live.
// Provenance: docs/dirty-south-venues.md. Keys distinguish branches.
const dirtyVenues = <String, String>{
  'Grindhouse Killer Burgers|Decatur':
      '433 North McDonough St, Decatur, GA 30030',
  'Grindhouse Killer Burgers|Piedmont Rd':
      '1842 Piedmont Ave NE, Atlanta, GA 30324',
  'Grindhouse Killer Burgers|Brookhaven':
      '2565 Apple Valley Road, Brookhaven, GA 30319',
  'Grindhouse Killer Burgers|Memorial Dr':
      '701 Memorial Drive SE, Atlanta, GA 30316',
  'Grindhouse Killer Burgers|West Midtown':
      '1221 Chattahoochee Ave NW, Atlanta, GA 30318',
  'Hotel Clermont|Poncey-Highland':
      '789 Ponce De Leon Ave NE, Atlanta, GA 30306',
  'Amasa|Alpharetta': '15 Academy Street, Space 1E, Alpharetta, GA 30009',
  'Chicheria|The Works': '202 Chattahoochee Row NW, Suite C, Atlanta, GA 30318',
  "Ormsby's|West Midtown": '1170 Howell Mill Rd, Suite P20, Atlanta, GA 30318',
  'Parkgrounds|Reynoldstown': '142 Flat Shoals Ave SE, Atlanta, GA 30316',
  'Punch Bowl Social|The Battery':
      '875 Battery Ave SE, Suite 720, Atlanta, GA 30339',
  'Sceptre Brewing Arts|Decatur':
      '630 East Lake Dr, Suite E, Decatur, GA 30030',
  'Wild Heaven|Avondale': '135B Maple St, Decatur, GA 30030',
  'Wild Heaven|Toco Hills': '2935-B N Druid Hills Rd, Atlanta, GA 30329',
  'Wild Heaven|West End': '1010 White St SW, Atlanta, GA 30310',
  'Breaker Breaker|Reynoldstown': '921 Wylie St SE, Atlanta, GA 30316',
  'Close Company|Old Fourth Ward':
      '505 North Angier Avenue, Suite 320, Atlanta, GA 30308',
  'Fado Buckhead|Buckhead': '273 Buckhead Ave NE, Atlanta, GA 30305',
  'Fado Midtown|Midtown': '933 Peachtree St NE, Atlanta, GA 30309',
  'Industry Tavern|Buckhead':
      '3280 Peachtree Road NE, Suite 187, Atlanta, GA 30305',
  "McCray's Tavern|Beltline": '670 DeKalb Ave NE, Suite 101, Atlanta, GA 30307',
  "McCray's Tavern|Midtown": '1163 W Peachtree Street NE, Atlanta, GA 30309',
  "McCray's Tavern|Smyrna": '4500 West Village Pl SE, Smyrna, GA 30080',
  'Monday Night Garage|West End': '933 Lee St SW, Atlanta, GA 30310',
  'Monday Night Brewing|West Midtown': '670 Trabert Ave NW, Atlanta, GA 30318',
  'Round Trip Brewing|Underwood Hills':
      '1279 Seaboard Industrial Blvd NW, Atlanta, GA 30318',
  'Round Trip Brewing|East Cobb':
      '4475 Roswell Rd, Suite 1600, Marietta, GA 30062',
  'Savage Pizza|Norcross': '7 Jones Street NW, Norcross, GA 30071',
  'The Family Dog|The Highlands':
      '1402 North Highland Avenue NE, Atlanta, GA 30306',
  'Blue Moon Brewery|The Battery': '755 Battery Ave SE, Atlanta, GA 30339',
  'Bone Garden Cantina|West Midtown':
      '1425 Ellsworth Industrial Blvd NW, Suite 6, Atlanta, GA 30318',
  'Little 5 Pub|Little 5 Points': '1174 Euclid Avenue NE, Atlanta, GA 30307',
  'Monks Meadery|The Highlands':
      '579 North Highland Avenue NE, Atlanta, GA 30307',
};

// US Census Public_AR_Current address-range coordinates; approximate.
const dirtyCoordinates = <String, (double, double)>{
  "Grindhouse Killer Burgers|Decatur": (33.772416, -84.29645),
  "Grindhouse Killer Burgers|Piedmont Rd": (33.806242, -84.366995),
  "Grindhouse Killer Burgers|Brookhaven": (33.861807, -84.336994),
  "Grindhouse Killer Burgers|Memorial Dr": (33.746622, -84.365152),
  "Grindhouse Killer Burgers|West Midtown": (33.800471, -84.425909),
  "Hotel Clermont|Poncey-Highland": (33.773749, -84.36118),
  "Amasa|Alpharetta": (34.075501, -84.293261),
  "Chicheria|The Works": (33.801152, -84.42415),
  "Ormsby's|West Midtown": (33.786533, -84.411755),
  "Parkgrounds|Reynoldstown": (33.750114, -84.354791),
  "Punch Bowl Social|The Battery": (33.88913, -84.46983),
  "Sceptre Brewing Arts|Decatur": (33.759752, -84.304992),
  "Wild Heaven|Avondale": (33.77625, -84.27635),
  "Wild Heaven|Toco Hills": (33.815377, -84.31018),
  "Wild Heaven|West End": (33.732159, -84.42057),
  "Breaker Breaker|Reynoldstown": (33.752444, -84.356123),
  "Close Company|Old Fourth Ward": (33.76905, -84.363543),
  "Fado Buckhead|Buckhead": (33.838149, -84.378659),
  "Fado Midtown|Midtown": (33.780312, -84.384068),
  "Industry Tavern|Buckhead": (33.842511, -84.363007),
  "McCray's Tavern|Beltline": (33.753431, -84.364386),
  "McCray's Tavern|Midtown": (33.786611, -84.387739),
  "McCray's Tavern|Smyrna": (33.844037, -84.490388),
  "Monday Night Garage|West End": (33.72916, -84.416065),
  "Monday Night Brewing|West Midtown": (33.794753, -84.412873),
  "Round Trip Brewing|Underwood Hills": (33.808636, -84.431197),
  "Round Trip Brewing|East Cobb": (33.986386, -84.421915),
  "Savage Pizza|Norcross": (33.942574, -84.213194),
  "The Family Dog|The Highlands": (33.79312, -84.351675),
  "Blue Moon Brewery|The Battery": (33.890928, -84.468992),
  "Bone Garden Cantina|West Midtown": (33.794503, -84.426969),
  "Little 5 Pub|Little 5 Points": (33.765461, -84.349249),
  "Monks Meadery|The Highlands": (33.769514, -84.352452),
};
