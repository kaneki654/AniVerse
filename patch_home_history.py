with open('app/templates/home.html', 'r') as f:
    content = f.read()

old_parse = """        let history = [];
        try {
            history = JSON.parse(localStorage.getItem('aniverse_history') || '[]');
        } catch (e) {
            console.error('Failed to parse history', e);
        }
        
        // Sort by timestamp desc
        history.sort((a, b) => b.timestamp - a.timestamp);"""

new_parse = """        let history = [];
        try {
            const raw = localStorage.getItem('aniverse_history');
            history = raw ? JSON.parse(raw) : [];
            if (!Array.isArray(history)) history = [];
        } catch (e) {
            console.error('Failed to parse history', e);
            history = [];
        }
        
        // Sort by timestamp desc
        history.sort((a, b) => b.timestamp - a.timestamp);"""

content = content.replace(old_parse, new_parse)
with open('app/templates/home.html', 'w') as f:
    f.write(content)
