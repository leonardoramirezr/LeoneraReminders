#!/usr/bin/env python3
"""Cliente mínimo de la API de App Store Connect para el workflow de builds.

Sólo usa la biblioteca estándar de Python y `openssl` (para firmar el JWT ES256).

Variables de entorno:
  ASC_KEY_ID, ASC_ISSUER_ID   identificadores de la clave de API
  ASC_KEY_PATH                ruta al .p8 (o ASC_KEY_P8 con su contenido)

Comandos:
  check                        comprueba que la clave funciona y que hay al menos un
                               dispositivo iOS registrado
  dev-cert-serials             imprime los seriales de los certificados "Apple Development"
                               que hay en el llavero (uno por línea)
  revoke-new-dev-certs ARCHIVO revoca por la API los certificados "Apple Development" del
                               llavero cuyo serial no aparece en ARCHIVO (la salida previa
                               de dev-cert-serials)
"""

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
DEV_CERT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def fail(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        fail(f"Falta la variable de entorno {name}.")
    return value


# --- JWT ---------------------------------------------------------------------------------

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """Convierte una firma ECDSA en DER (SEQUENCE { INTEGER r, INTEGER s }) a r||s de 64 bytes."""

    def read_length(i):
        length = der[i]
        i += 1
        if length & 0x80:
            count = length & 0x7F
            length = int.from_bytes(der[i:i + count], "big")
            i += count
        return length, i

    if der[0] != 0x30:
        raise ValueError("firma DER inválida")
    _, i = read_length(1)
    parts = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("firma DER inválida")
        length, i = read_length(i + 1)
        parts.append(int.from_bytes(der[i:i + length], "big"))
        i += length
    return b"".join(p.to_bytes(32, "big") for p in parts)


def key_path():
    path = os.environ.get("ASC_KEY_PATH", "").strip()
    if path:
        return path
    content = env("ASC_KEY_P8")
    if "BEGIN" not in content:
        content = base64.b64decode(content).decode()
    handle = tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False)
    handle.write(content.strip() + "\n")
    handle.close()
    os.environ["ASC_KEY_PATH"] = handle.name
    return handle.name


def make_token():
    now = int(time.time())
    header = {"alg": "ES256", "kid": env("ASC_KEY_ID"), "typ": "JWT"}
    payload = {"iss": env("ASC_ISSUER_ID"), "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload)
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path()],
        input=signing_input.encode(),
        capture_output=True,
    )
    if result.returncode != 0:
        fail("openssl no pudo firmar el JWT; ¿ASC_KEY_P8 es el contenido completo del .p8? "
             + result.stderr.decode().strip())
    return f"{signing_input}.{b64url(der_to_raw(result.stdout))}"


# --- HTTP --------------------------------------------------------------------------------

_token = None


def request(method, url, params=None):
    global _token
    if _token is None:
        _token = make_token()
    if not url.startswith("http"):
        url = API + url
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {_token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors) or detail
        except ValueError:
            pass
        hint = ""
        if error.code == 401:
            hint = (" Revisa ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (debe ser una Team Key, no una"
                    " Individual Key, y no estar revocada).")
        elif error.code == 403:
            hint = " La clave no tiene permisos suficientes: necesita el rol Admin."
        fail(f"App Store Connect respondió {error.code} a {method} {url}: {detail}.{hint}")
    except urllib.error.URLError as error:
        fail(f"No se pudo conectar con App Store Connect: {error.reason}")


def get_all(path, params):
    items, url = [], path
    while url:
        page = request("GET", url, params if url == path else None)
        items.extend(page.get("data", []))
        url = page.get("links", {}).get("next")
    return items


# --- Llavero -----------------------------------------------------------------------------

def normalize_serial(serial):
    return serial.strip().upper().replace(":", "").lstrip("0")


def keychain_dev_serials():
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        capture_output=True, text=True,
    )
    # Sin certificados, `security` termina con error: es una lista vacía.
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", result.stdout, re.S)
    serials = set()
    for pem in pems:
        out = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"], input=pem, capture_output=True, text=True, check=True
        ).stdout
        serials.add(normalize_serial(out.split("=", 1)[1]))
    return serials


# --- Comandos ----------------------------------------------------------------------------

def cmd_check():
    devices = get_all("/v1/devices", {
        "filter[platform]": "IOS",
        "filter[status]": "ENABLED",
        "fields[devices]": "name,deviceClass,model",
        "limit": 200,
    })
    print("La clave de App Store Connect funciona.")
    print(f"Dispositivos iOS registrados y activos: {len(devices)}")
    for device in devices:
        attrs = device["attributes"]
        print(f"  - {attrs.get('name')} ({attrs.get('model') or attrs.get('deviceClass')})")
    if not devices:
        fail("No hay ningún dispositivo iOS registrado en Apple Developer: un perfil Ad Hoc necesita"
             " al menos uno. Registra el UDID del iPhone en Certificates, Identifiers & Profiles › Devices.")


def cmd_dev_cert_serials():
    for serial in sorted(keychain_dev_serials()):
        print(serial)


def cmd_revoke_new_dev_certs(before_path):
    if not os.path.exists(before_path):
        print("No hay lista previa de certificados: no se revoca nada.")
        return
    with open(before_path) as handle:
        before = {normalize_serial(line) for line in handle if line.strip()}
    new = keychain_dev_serials() - before
    if not new:
        print("xcodebuild no creó certificados de desarrollo nuevos.")
        return
    certificates = get_all("/v1/certificates", {
        "fields[certificates]": "serialNumber,certificateType,name,expirationDate",
        "limit": 200,
    })
    by_serial = {normalize_serial(c["attributes"]["serialNumber"]): c for c in certificates}
    for serial in sorted(new):
        cert = by_serial.get(serial)
        if cert is None:
            print(f"El certificado {serial} no existe en la cuenta (ya revocado o de otro equipo).")
            continue
        if cert["attributes"]["certificateType"] not in DEV_CERT_TYPES:
            print(f"El certificado {serial} no es de desarrollo; no se toca.")
            continue
        request("DELETE", f"/v1/certificates/{cert['id']}")
        print(f"Revocado el certificado de desarrollo temporal {cert['attributes'].get('name')} ({serial}).")


def main(argv):
    if len(argv) >= 2 and argv[1] == "check":
        cmd_check()
    elif len(argv) >= 2 and argv[1] == "dev-cert-serials":
        cmd_dev_cert_serials()
    elif len(argv) == 3 and argv[1] == "revoke-new-dev-certs":
        cmd_revoke_new_dev_certs(argv[2])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
