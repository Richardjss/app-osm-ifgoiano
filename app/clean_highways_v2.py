import xml.etree.ElementTree as ET

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

tree = ET.parse('../backend/campus_original.osm')
root = tree.getroot()
nodes = {}
for node in root.findall('node'):
    nodes[node.get('id')] = (float(node.get('lon')), float(node.get('lat')))

uni_poly = []
for way in root.findall('way'):
    if way.get('id') == '727671838':
        for nd in way.findall('nd'):
            uni_poly.append(nodes[nd.get('ref')])
        break

lon_e, lat_e = -50.907289, -17.803512

removed = 0
for way in root.findall('way'):
    is_highway = False
    for tag in way.findall('tag'):
        if tag.get('k') == 'highway':
            is_highway = True
            break
            
    if is_highway and way.get('id') != '727671838':
        keep = False
        for nd in way.findall('nd'):
            ref = nd.get('ref')
            if ref in nodes:
                lon, lat = nodes[ref]
                if point_in_polygon(lon, lat, uni_poly):
                    keep = True
                    break
                # Distance to entrance roughly < 100 meters
                # 1 degree lat is ~111km, so 100m is ~0.0009 degrees
                if abs(lon - lon_e) < 0.001 and abs(lat - lat_e) < 0.001:
                    keep = True
                    break
        
        if not keep:
            root.remove(way)
            removed += 1

tree.write('../backend/campus_clean.osm', encoding='utf-8', xml_declaration=True)
print(f'Removed {removed} external highways.')
