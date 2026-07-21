import xml.etree.ElementTree as ET

osm_file = '../backend/campus.osm'
tree = ET.parse(osm_file)
root = tree.getroot()

removed_count = 0
for way in root.findall('way'):
    for tag in way.findall('tag'):
        if tag.get('k') == 'name':
            v = tag.get('v')
            if 'Avenida' in v and ('Sul' in v or 'Presidente' in v or 'Lauro' in v or 'Flamboyant' in v or 'Mota' in v or 'Bougainville' in v or 'Oeste' in v or 'Evangelino' in v):
                root.remove(way)
                removed_count += 1
                break

tree.write('../backend/campus_clean.osm', encoding='utf-8', xml_declaration=True)
print(f'Removed {removed_count} external avenue ways.')
