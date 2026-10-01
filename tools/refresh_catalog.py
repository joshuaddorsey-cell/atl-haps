"""Refresh bundled listings from public calendars. Standard library + lxml.
No images downloaded, account tokens, or private APIs used.
"""
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.parse import urlparse, parse_qs
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from lxml import html
import json

ROOT=Path(__file__).resolve().parents[1]
def fetch(url):
    with urlopen(Request(url,headers={'User-Agent':'ATL Haps local calendar reader'}),timeout=20) as r:
        return html.fromstring(r.read())
def category(text):
    s=text.lower()
    for key,value in [('trivia','Trivia'),('karaoke','Nightlife'),('nightlife','Nightlife'),('bingo','Nightlife'),('festival','Festivals'),('parade','Festivals'),('sport','Sports'),('braves','Sports'),('hawks','Sports'),('museum','Arts'),('art ','Arts'),('film','Arts'),('market','Community'),('family','Community')]:
        if key in s:return value
    return 'Music'
def text(p,cls):
    nodes=p.xpath(f'.//*[contains(concat(" ",normalize-space(@class)," ")," {cls} ")]')
    return nodes[0].text_content().strip() if nodes else ''
events=[]
star=fetch('https://www.starbaratl.bar/')
for card in star.xpath('//article[contains(@class,"eventlist-event")]'):
    try:
        link=card.xpath('.//a[contains(@class,"eventlist-title-link")]')[0]
        dates=card.xpath('.//a[contains(@class,"eventlist-meta-export-google")]/@href')[0]
        ds=parse_qs(urlparse(dates).query)['dates'][0].split('/')
        start,end=[datetime.strptime(d,'%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc) for d in ds]
        desc=text(card,'eventlist-excerpt')
        title=link.text_content().strip()
        # Use concise factual summaries, with original details linked in the app.
        events.append(dict(id='https://www.starbaratl.bar'+link.get('href'),title=title,
            venue='Star Community Bar',address='437 Moreland Ave NE, Atlanta, GA 30307',
            category=category(title+' '+desc),description='Live event at Star Community Bar. See the organizer for performers, admission, and any schedule changes.',
            url='https://www.starbaratl.bar'+link.get('href'),source='Star Community Bar',
            start=start.isoformat(),end=end.isoformat(),latitude=33.7661,longitude=-84.3491))
    except Exception:pass
cal=fetch('https://www.theatlantacalendar.com/')
links=list(dict.fromkeys(cal.xpath('//a[starts-with(@href,"/events/")]/@href')))
def detail(path):
    if path=='/events/new':return []
    try:
        p=fetch('https://www.theatlantacalendar.com'+path)
        out=[]
        for script in p.xpath('//script[@type="application/ld+json"]'):
            node=json.loads(script.text)
            if not isinstance(node,dict) or node.get('@type')!='Event':continue
            start=datetime.fromisoformat(node['startDate'].replace('Z','+00:00'))
            if start.year<2026:continue
            loc=node.get('location',{})
            address=loc.get('address','')
            if isinstance(address,dict):address=', '.join(str(address[k]) for k in ['streetAddress','addressLocality','addressRegion','postalCode'] if address.get(k))
            if not address:continue
            end=node.get('endDate')
            title=node['name']
            out.append(dict(id='https://www.theatlantacalendar.com'+path,title=title,
                venue=loc.get('name','Event venue'),address=address,category=category(title+' '+node.get('description','')),
                description='See the organizer listing for admission, full details, and any updates.',url='https://www.theatlantacalendar.com'+path,
                source='The Atlanta Calendar',start=start.isoformat(),end=end))
        return out
    except Exception:return []
with ThreadPoolExecutor(max_workers=6) as pool:
    for items in pool.map(detail,links[:45]):events.extend(items)
for weekday,hour,minute,title,cat in [(3,20,0,'Thursday trivia at Home Bar','Trivia'),(2,19,30,'Music bingo at Home Bar','Nightlife'),(5,21,0,'Saturday karaoke at Home Bar','Nightlife'),(1,19,0,'Old-time jam at Home Bar','Music')]:
    # Oct 1 2026 is Thursday. This anchor represents a weekday/time, not a promised dated occurrence.
    day={3:1,2:7,5:3,1:6}[weekday]
    events.append(dict(id='homebar-'+str(weekday),title=title,venue="Bob & Harriet’s Home Bar",
        address='1992 Hosea L Williams Dr NE, Atlanta, GA 30317',category=cat,
        description='A recurring neighborhood bar event. Start time published by the venue; end time and admission are not published. Confirm this week with the venue.',
        url='https://www.homebaratl.com/',source='Home Bar',start=f'2026-10-{day:02}T{hour:02}:{minute:02}:00',end=None,
        latitude=33.7524,longitude=-84.3227,recurring=True))
(ROOT/'assets/events.json').write_text(json.dumps(events,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'Saved {len(events)} sourced listings')
