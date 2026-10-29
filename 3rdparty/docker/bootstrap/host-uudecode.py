#!/usr/bin/env python3
import argparse
import base64
import binascii
import sys

parser = argparse.ArgumentParser()
parser.add_argument("-o", "--output", dest="output")
parser.add_argument("input")
args = parser.parse_args()
mode = None
started = False
try:
    with open(args.input, "rb") as source:
        payload = bytearray()
        for line in source:
            line = line.rstrip(b"\r\n")
            if line.startswith(b"begin-base64 "):
                mode = "base64"
                started = True
                continue
            if line.startswith(b"begin "):
                mode = "uu"
                started = True
                continue
            if not started:
                continue
            if mode == "base64":
                if line.strip() == b"====":
                    break
                if line:
                    payload.extend(base64.b64decode(line, validate=False))
            else:
                if line.strip() == b"end":
                    break
                if line:
                    payload.extend(binascii.a2b_uu(line))
    if not started:
        raise ValueError("no uuencoded begin header")
    if args.output is None:
        raise ValueError("an output path is required")
    with open(args.output, "wb") as output:
        output.write(payload)
except (OSError, ValueError, binascii.Error) as error:
    print(f"uudecode: {error}", file=sys.stderr)
    sys.exit(1)
