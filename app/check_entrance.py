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

lon, lat = -50.907289, -17.803512
print("Is entrance inside?", point_in_polygon(lon, lat, uni_poly))
