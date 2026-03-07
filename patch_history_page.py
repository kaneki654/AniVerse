with open('app/templates/history.html', 'r') as f:
    content = f.read()

old_parse = """        function getHistory() {
            const history = localStorage.getItem('aniverse_history');
            return history ? JSON.parse(history) : [];
        }"""

new_parse = """        function getHistory() {
            try {
                const raw = localStorage.getItem('aniverse_history');
                const history = raw ? JSON.parse(raw) : [];
                return Array.isArray(history) ? history : [];
            } catch (e) {
                return [];
            }
        }"""

content = content.replace(old_parse, new_parse)
with open('app/templates/history.html', 'w') as f:
    f.write(content)
