{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "slimbrave-neo";
  version = "unstable-32f5d96";
  src = fetchFromGitHub {
    owner = "ChaoticSi1ence";
    repo = "SlimBrave-Neo";
    rev = "32f5d96a3cb7ed3deb38e55f34cb003aa2af58e3";
    hash = "sha256-F4nsEop6O6iaQv+kXZ/BjaAkX0ppqeUrKtCw+RavdUQ=";
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/slimbrave-neo $out/bin
    cp slimbrave-linux.py $out/share/slimbrave-neo/
    cp -r Presets $out/share/slimbrave-neo/
    substituteInPlace $out/share/slimbrave-neo/slimbrave-linux.py \
      --replace-fail 'default="./Presets/"' 'default="'$out'/share/slimbrave-neo/Presets/"'
    makeWrapper ${python3}/bin/python3 $out/bin/slimbrave-neo \
      --add-flags "$out/share/slimbrave-neo/slimbrave-linux.py" \
      --prefix PATH : /etc/profiles/per-user/gapul/bin
    runHook postInstall
  '';
  meta = {
    description = "Interactive Brave enterprise policy editor";
    homepage = "https://github.com/ChaoticSi1ence/SlimBrave-Neo";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "slimbrave-neo";
  };
}
