import json
import base64
import blackboxprotobuf

try:
    with open('logs/R3CN10BZ7PD/20260419/205657_20109650/078_POST_mapmobileapps_trafficjam_location.json') as f:
        j = json.load(f)

    raw_b64 = j['request']['body']['_raw'][7:]
    raw_bytes = base64.b64decode(raw_b64)

    dec, mt = blackboxprotobuf.decode_message(raw_bytes)

    print('Type of keys in dec:', [type(k) for k in dec.keys()])
    if 2 in dec:
        print('Type of keys in dec[2][0]:', [type(k) for k in dec[2][0].keys()])
    elif '2' in dec:
        print('Type of keys in dec["2"][0]:', [type(k) for k in dec['2'][0].keys()])
except Exception as e:
    print(f"Error: {e}")
