{ python313, fetchPypi }:
let
  # PyIMG4 0.8.8 is incompatible with ASN.1 3.x. Scope the compatible
  # dependency to this tool rather than permitting broken packages globally.
  python = python313.override {
    packageOverrides = final: prev: {
      asn1 = prev.asn1.overridePythonAttrs {
        version = "2.8.0";
        src = fetchPypi {
          pname = "asn1";
          version = "2.8.0";
          hash = "sha256:adf77ddc2707cf420c0eae3b99ee30e913afcf0936467d42669820ce6b7d150a";
        };
      };
    };
  };
in
python.pkgs.pymobiledevice3
