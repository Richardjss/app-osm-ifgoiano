import xml.etree.ElementTree as ET
import json
import os

osm_file = '../backend/campus.osm'
output_file = 'assets/pois.json'

if not os.path.exists('assets'):
    os.makedirs('assets')

def point_in_polygon(x, y, poly):
    n = len(poly)
    inside = False
    p1x, p1y = poly[0]
    for i in range(n + 1):
        p2x, p2y = poly[i % n]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside

def format_toilet_name(name, tags):
    if tags.get('amenity') == 'toilets':
        if not name:
            name = 'Banheiro'
        if tags.get('female') == 'yes' and tags.get('male') != 'yes' and '(F)' not in name:
            name += ' (F)'
        elif tags.get('male') == 'yes' and tags.get('female') != 'yes' and '(M)' not in name:
            name += ' (M)'
    return name

def get_generic_name(tags):
    if tags.get('amenity') == 'toilets':
        return 'Banheiro'
    room = tags.get('room')
    if room == 'class':
        return 'Sala de Aula'
    if room == 'office':
        return 'Escrit\u00f3rio'
    if room == 'laboratory':
        return 'Laborat\u00f3rio'
    if room == 'kitchen':
        return 'Cozinha'
    if room == 'storage':
        return 'Dep\u00f3sito'
    if tags.get('indoor') == 'room' or 'room' in tags:
        return 'Sala'
    return None

tree = ET.parse(osm_file)
root = tree.getroot()

pois = []
nodes = {}
raw_rooms = []
crosswalks = []

for node in root.findall('node'):
    nid = node.get('id')
    lat = float(node.get('lat'))
    lon = float(node.get('lon'))
    
    tags = {tag.get('k'): tag.get('v') for tag in node.findall('tag')}
    nodes[nid] = (lat, lon, tags)
    
    # Detecção de faixas de pedestre
    if tags.get('highway') == 'crossing':
        crosswalks.append({'id': nid, 'lat': lat, 'lon': lon})
    
    name = tags.get('name')
    name = format_toilet_name(name, tags)
    is_room = tags.get('indoor') == 'room' or 'room' in tags or tags.get('amenity') == 'toilets'
    
    if is_room:
        if not name:
            name = get_generic_name(tags)
        if name:
            raw_rooms.append({'id': nid, 'name': name, 'lat': lat, 'lon': lon, 'tag': tags.get('room'), 'short_name': tags.get('short_name'), 'alt_name': tags.get('alt_name'), 'description': tags.get('description')})
    elif name:
        pois.append({'name': name, 'lat': lat, 'lon': lon, 'type': 'node', 'rooms': [], 'short_name': tags.get('short_name'), 'alt_name': tags.get('alt_name'), 'description': tags.get('description')})

for way in root.findall('way'):
    tags = {tag.get('k'): tag.get('v') for tag in way.findall('tag')}
    
    is_room = tags.get('indoor') == 'room' or 'room' in tags or tags.get('amenity') == 'toilets'
    name = tags.get('name')
    name = format_toilet_name(name, tags)
    
    way_lats = []
    way_lons = []
    entrances = []
    main_entrance = None
    
    for nd in way.findall('nd'):
        nid = nd.get('ref')
        if nid in nodes:
            lat, lon, ntags = nodes[nid]
            if 'entrance' in ntags:
                entrance_type = ntags['entrance']
                ent_data = {'lat': lat, 'lon': lon, 'type': entrance_type}
                if 'wheelchair' in ntags:
                    ent_data['wheelchair'] = ntags['wheelchair']
                entrances.append(ent_data)
                if entrance_type == 'main':
                    main_entrance = {'lat': lat, 'lon': lon}
            way_lats.append(lat)
            way_lons.append(lon)
            
    if way_lats and way_lons:
        avg_lat = sum(way_lats) / len(way_lats)
        avg_lon = sum(way_lons) / len(way_lons)
        
        if is_room:
            if not name:
                name = get_generic_name(tags)
            if name:
                raw_rooms.append({
                    'id': way.get('id'),
                    'name': name, 
                    'lat': avg_lat, 
                    'lon': avg_lon,
                    'tag': tags.get('room'),
                    'short_name': tags.get('short_name'),
                    'alt_name': tags.get('alt_name'),
                    'description': tags.get('description')
                })
        elif name:
            polygon = [[lat, lon] for lat, lon in zip(way_lats, way_lons)]
            
            if main_entrance:
                target_lat = main_entrance['lat']
                target_lon = main_entrance['lon']
            elif entrances:
                target_lat = entrances[0]['lat']
                target_lon = entrances[0]['lon']
            else:
                target_lat = avg_lat
                target_lon = avg_lon
            
            pois.append({
                'name': name, 
                'lat': target_lat, 
                'lon': target_lon, 
                'type': 'way', 
                'polygon': polygon,
                'entrances': entrances,
                'rooms': [],
                'short_name': tags.get('short_name'),
                'alt_name': tags.get('alt_name'),
                'description': tags.get('description')
            })

for room in raw_rooms:
    assigned = False
    for poi in pois:
        if poi['type'] == 'way' and 'polygon' in poi:
            if point_in_polygon(room['lon'], room['lat'], [[p[1], p[0]] for p in poi['polygon']]):
                poi['rooms'].append(room)
                assigned = True
                break

for poi in pois:
    if 'rooms' in poi:
        poi['rooms'].sort(key=lambda x: x['name'])

pois.sort(key=lambda x: x['name'])

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(pois, f, ensure_ascii=False, indent=2)

with open('assets/crosswalks.json', 'w', encoding='utf-8') as f:
    json.dump(crosswalks, f, ensure_ascii=False, indent=2)

print(f"Sucesso: {len(pois)} locais, {len(raw_rooms)} salas e {len(crosswalks)} faixas processados!")
