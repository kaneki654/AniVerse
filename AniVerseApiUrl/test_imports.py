import sys

try:
    import Crypto.Cipher
    print("Crypto.Cipher imported successfully")
except Exception as e:
    print(f"Error importing Crypto.Cipher: {e}", file=sys.stderr)

try:
    import app.main
    print("app.main imported successfully")
except Exception as e:
    print(f"Error importing app.main: {e}", file=sys.stderr)
