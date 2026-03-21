import urllib.request
import urllib.parse

url = "http://localhost:8000/auth/login"
data = urllib.parse.urlencode({
    'username': 'aarushkhanna11@gmail.com',
    'password': '$81Premium'
}).encode('utf-8')

headers = {'Content-Type': 'application/x-www-form-urlencoded'}
req = urllib.request.Request(url, data=data, headers=headers)

try:
    with urllib.request.urlopen(req) as response:
        print(f"Status: {response.status}")
        print(response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(f"HTTP Error: {e.code}")
    print(e.read().decode('utf-8'))
