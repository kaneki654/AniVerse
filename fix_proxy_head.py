import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_return = """        return StreamingResponse(
            stream_generator(),
            status_code=status_code,
            headers=resp_headers,
            media_type=head_resp.headers.get("Content-Type", "video/mp4")
        )"""

new_return = """        if request.method == "HEAD":
            return Response(content="", status_code=status_code, headers=resp_headers, media_type=head_resp.headers.get("Content-Type", "video/mp4"))

        return StreamingResponse(
            stream_generator(),
            status_code=status_code,
            headers=resp_headers,
            media_type=head_resp.headers.get("Content-Type", "video/mp4")
        )"""

if old_return in content:
    content = content.replace(old_return, new_return)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed proxy_stream to support HEAD properly!")
else:
    print("Could not find the return statement to replace.")
