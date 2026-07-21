import xml.etree.ElementTree as ET

tree = ET.parse('../backend/campus_original.osm')
root = tree.getroot()
nodes = {}
for node in root.findall('node'):
    nodes[node.get('id')] = (float(node.get('lon')), float(node.get('lat')))

lon_e, lat_e = -50.907289, -17.803512

for way in root.findall('way'):
    is_highway = False
    name = None
    for tag in way.findall('tag'):
        if tag.get('k') == 'highway':
            is_highway = True
        if tag.get('k') == 'name':
            name = tag.get('v')
            
    if is_highway:
        min_dist = 999999
        for nd in way.findall('nd'):
            ref = nd.get('ref')
            if ref in nodes:
                lon, lat = nodes[ref]
                dist = (lon - lon_e)**2 + (lat - lat_e)**2
                if dist < min_dist:
                    min_dist = dist
        if min_dist < 0.000001:
            print(f"Highway near entrance: ID={way.get('id')}, Name={name}")
