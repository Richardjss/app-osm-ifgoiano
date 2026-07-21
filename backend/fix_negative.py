import re
import sys

def main():
    filename = 'campus_clean.osm'
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    def repl_id(m):
        val = int(m.group(1))
        # Use the same quote character that was matched
        return 'id="' + str(-val + 1000000000) + '"'

    def repl_ref(m):
        val = int(m.group(1))
        return 'ref="' + str(-val + 1000000000) + '"'

    # Support both single and double quotes
    content = re.sub(r"id=['\"](-\d+)['\"]", repl_id, content)
    content = re.sub(r"ref=['\"](-\d+)['\"]", repl_ref, content)
    # also handle 'nd ref' which might have spaces
    content = re.sub(r"nd\s+ref=['\"](-\d+)['\"]", lambda m: 'nd ref="' + str(-int(m.group(1)) + 1000000000) + '"', content)

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print("Fixed negative IDs in campus_clean.osm (including single quotes)")

if __name__ == '__main__':
    main()
