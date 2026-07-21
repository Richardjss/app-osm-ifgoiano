import xml.etree.ElementTree as ET
tree = ET.parse('../backend/campus.osm')
root = tree.getroot()

residential_names = []
for way in root.findall('way'):
    is_residential = False
    name = None
    for tag in way.findall('tag'):
        if tag.get('k') == 'highway' and tag.get('v') == 'residential':
            is_residential = True
        if tag.get('k') == 'name':
            name = tag.get('v')
    if is_residential and name:
        residential_names.append(name)

print(sorted(list(set(residential_names)))[:30])
