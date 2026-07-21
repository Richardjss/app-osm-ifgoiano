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

internal_names = set()
for way in root.findall('way'):
    is_highway = False
    name = None
    for tag in way.findall('tag'):
        if tag.get('k') == 'highway':
            is_highway = True
        if tag.get('k') == 'name':
            name = tag.get('v')
            
    if is_highway and name:
        any_inside = False
        for nd in way.findall('nd'):
            ref = nd.get('ref')
            if ref in nodes:
                lon, lat = nodes[ref]
                if point_in_polygon(lon, lat, uni_poly):
                    any_inside = True
                    break
        if any_inside:
            internal_names.add(name)

print("Internal highway names:")
print(internal_names)
