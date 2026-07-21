import xml.etree.ElementTree as ET

tree = ET.parse('../backend/campus.osm')
root = tree.getroot()

for elem in root:
    is_uni = False
    name = ''
    for tag in elem.findall('tag'):
        if tag.get('k') == 'amenity' and tag.get('v') == 'university':
            is_uni = True
        if tag.get('k') == 'name':
            name = tag.get('v')
    if is_uni:
        print(f"Type: {elem.tag}, ID: {elem.get('id')}, Name: {name}")

