import xml.etree.ElementTree as ET
from collections import defaultdict, deque

tree = ET.parse('../backend/campus.osm')
root = tree.getroot()

adj = defaultdict(set)
for way in root.findall('way'):
    is_highway = False
    for tag in way.findall('tag'):
        if tag.get('k') == 'highway':
            is_highway = True
            break
    if is_highway:
        nds = [nd.get('ref') for nd in way.findall('nd')]
        for i in range(len(nds)-1):
            adj[nds[i]].add(nds[i+1])
            adj[nds[i+1]].add(nds[i])

visited = set()
components = []
for node in adj.keys():
    if node not in visited:
        comp = []
        q = deque([node])
        visited.add(node)
        while q:
            curr = q.popleft()
            comp.append(curr)
            for nxt in adj[curr]:
                if nxt not in visited:
                    visited.add(nxt)
                    q.append(nxt)
        components.append(len(comp))

print('Connected components (by number of nodes):')
print(sorted(components, reverse=True))
