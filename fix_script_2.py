py_path = 'app/main.py'
with open(py_path, 'r') as f:
    py_content = f.read()

bad_line = '                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page[\\\'img\\\'], safe=\\\'\\\')}"'
good_line = '                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page[\'img\'], safe=\'\')}"'

py_content = py_content.replace(bad_line, good_line)

with open(py_path, 'w') as f:
    f.write(py_content)
print("Fixed syntax")
