import xml.etree.ElementTree as ET
import json

tree = ET.parse('../backend/campus.osm')
root = tree.getroot()

nodes = {}
rooms = []

for node in root.findall('node'):
    nid = node.get('id')
    lat = float(node.get('lat'))
    lon = float(node.get('lon'))
    tags = {t.get('k'): t.get('v') for t in node.findall('tag')}
    nodes[nid] = (lat, lon, tags)
    
    is_room = tags.get('indoor') == 'room' or 'room' in tags
    is_toilet = tags.get('amenity') == 'toilets'
    
    if is_room or is_toilet:
        name = tags.get('name')
        if not name and is_toilet:
            name = 'Banheiro'
        if name:
            rooms.append({'id': nid, 'name': name, 'lat': lat, 'lon': lon})

print(f"Encontrou {len(rooms)} salas/banheiros que são nós.")

for way in root.findall('way'):
    tags = {t.get('k'): t.get('v') for t in way.findall('tag')}
    is_room = tags.get('indoor') == 'room' or 'room' in tags
    is_toilet = tags.get('amenity') == 'toilets'
    
    if is_room or is_toilet:
        name = tags.get('name')
        if not name and is_toilet:
            name = 'Banheiro'
        if name:
            lats = []
            lons = []
            for nd in way.findall('nd'):
                ref = nd.get('ref')
                if ref in nodes:
                    lats.append(nodes[ref][0])
                    lons.append(nodes[ref][1])
            if lats:
                rooms.append({
                    'id': way.get('id'),
                    'name': name, 
                    'lat': sum(lats)/len(lats), 
                    'lon': sum(lons)/len(lons)
                })

print(f"Total: {len(rooms)} salas/banheiros.")
print(rooms[:5])
