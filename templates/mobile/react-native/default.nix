# React Native Development Environment
# Complete setup for iOS and Android development with Expo

{ pkgs ? import <nixpkgs> {
    config = {
      android_sdk.accept_license = true;
      allowUnfree = true;
    };
  }
, lib ? pkgs.lib
, stdenv ? pkgs.stdenv
}:

let
  # Android SDK configuration
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    cmdLineToolsVersion = "8.0";
    toolsVersion = "26.1.1";
    platformToolsVersion = "34.0.4";
    buildToolsVersions = [ "34.0.0" "33.0.2" "33.0.1" ];
    includeEmulator = true;
    emulatorVersion = "32.1.15";
    platformVersions = [ "34" "33" "32" "31" "30" "29" "28" ];
    includeSources = false;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "armeabi-v7a" "arm64-v8a" "x86" "x86_64" ];
    cmakeVersions = [ "3.22.1" ];
    includeNDK = true;
    ndkVersions = ["25.1.8937393"];
    useGoogleAPIs = false;
    useGoogleTVAddOns = false;
    includeExtras = [
      "extras;android;m2repository"
      "extras;google;m2repository"
    ];
  };

  # iOS development dependencies (macOS only)
  iosDeps = lib.optionals stdenv.isDarwin (with pkgs; [
    cocoapods
    ios-deploy
    idb-companion
    xcpretty
    darwin.xcode
  ]);

  # Development shell script
  setupScript = pkgs.writeShellScriptBin "setup-react-native" ''
    set -e
    
    echo "🚀 Setting up React Native development environment..."
    
    # Create project directories
    mkdir -p android ios
    
    # Set Android environment variables
    export ANDROID_SDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_AVD_HOME="$HOME/.android/avd"
    export PATH="$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
    
    # Check Android setup
    echo "📱 Checking Android SDK..."
    adb version
    
    ${lib.optionalString stdenv.isDarwin ''
    # iOS setup (macOS only)
    echo "🍎 Checking iOS tools..."
    if command -v xcodebuild >/dev/null 2>&1; then
      xcodebuild -version
    else
      echo "⚠️  Xcode not found. Please install Xcode from the App Store."
    fi
    
    # Install iOS dependencies
    if command -v pod >/dev/null 2>&1; then
      echo "✅ CocoaPods is available"
    else
      echo "⚠️  CocoaPods not found"
    fi
    ''}
    
    # Install Node.js dependencies
    echo "📦 Installing Node.js packages..."
    npm install -g @expo/cli@latest
    npm install -g @react-native-community/cli
    npm install -g eas-cli
    
    # Verify installations
    echo "🔍 Verifying installations..."
    node --version
    npm --version
    expo --version
    react-native --version
    eas --version
    
    echo "✅ React Native development environment is ready!"
    echo ""
    echo "📚 Quick start commands:"
    echo "  npx create-expo-app MyApp --template blank-typescript"
    echo "  cd MyApp"
    echo "  npm start"
    echo ""
    echo "🛠️ Available tools:"
    echo "  Android SDK: $ANDROID_SDK_ROOT"
    echo "  Platform tools: $ANDROID_SDK_ROOT/platform-tools"
    echo "  Build tools: $ANDROID_SDK_ROOT/build-tools"
    
    ${lib.optionalString stdenv.isDarwin ''
    echo "  iOS Simulator: Available through Xcode"
    echo "  CocoaPods: $(which pod)"
    ''}
  '';

  # Development scripts
  devScripts = pkgs.writeShellScriptBin "rn-dev" ''
    case "$1" in
      android)
        echo "🤖 Starting Android development..."
        npx expo run:android
        ;;
      ios)
        echo "🍎 Starting iOS development..."
        npx expo run:ios
        ;;
      web)
        echo "🌐 Starting web development..."
        npx expo start --web
        ;;
      emulator)
        echo "📱 Starting Android emulator..."
        $ANDROID_SDK_ROOT/emulator/emulator -list-avds
        echo "Choose an AVD from the list above and run:"
        echo "$ANDROID_SDK_ROOT/emulator/emulator -avd <AVD_NAME>"
        ;;
      build)
        echo "🏗️ Building with EAS..."
        eas build --platform all
        ;;
      submit)
        echo "🚀 Submitting to app stores..."
        eas submit --platform all
        ;;
      doctor)
        echo "🩺 Running health checks..."
        npx expo doctor
        npx react-native doctor
        ;;
      clean)
        echo "🧹 Cleaning project..."
        rm -rf node_modules
        rm -rf .expo
        rm -rf android/build
        rm -rf ios/build
        npm install
        ;;
      *)
        echo "📱 React Native Development Commands"
        echo ""
        echo "Usage: rn-dev <command>"
        echo ""
        echo "Commands:"
        echo "  android    Start Android development"
        echo "  ios        Start iOS development"
        echo "  web        Start web development"
        echo "  emulator   List and start Android emulators"
        echo "  build      Build with EAS Build"
        echo "  submit     Submit to app stores"
        echo "  doctor     Run health checks"
        echo "  clean      Clean project and reinstall dependencies"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "react-native-dev";
  
  buildInputs = with pkgs; [
    # Core development tools
    nodejs_20
    yarn
    npm
    git
    jq
    curl
    unzip
    
    # Android development
    androidComposition.androidsdk
    openjdk17
    gradle
    
    # iOS development (macOS only)
  ] ++ iosDeps ++ [
    
    # React Native tools
    watchman
    
    # Development utilities
    setupScript
    devScripts
    
    # Testing and debugging
    python3
    
    # Additional tools
    rsync
    which
  ];

  shellHook = ''
    # Android SDK environment
    export ANDROID_SDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_AVD_HOME="$HOME/.android/avd"
    export ANDROID_EMULATOR_USE_SYSTEM_GL=1
    export PATH="$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
    
    # Java environment for Android
    export JAVA_HOME="${pkgs.openjdk17}/lib/openjdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    
    # React Native environment
    export REACT_NATIVE_PACKAGER_HOSTNAME="localhost"
    export EXPO_USE_FAST_RESOLVER=1
    export FLIPPER_DISABLE_PLUGIN_AUTO_UPDATE=1
    
    ${lib.optionalString stdenv.isDarwin ''
    # iOS environment (macOS only)
    export IOS_SIMULATOR_UDID=""
    export RCT_NO_LAUNCH_PACKAGER=1
    ''}
    
    # Development environment
    export NODE_ENV="development"
    export EXPO_DEBUG=1
    
    echo "🚀 React Native Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📱 Android SDK: $ANDROID_SDK_ROOT"
    echo "☕ Java: $JAVA_HOME"
    echo "📦 Node.js: $(node --version)"
    echo "🔧 npm: $(npm --version)"
    ${lib.optionalString stdenv.isDarwin ''
    echo "🍎 iOS tools: Available"
    ''}
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-react-native  # Initial environment setup"
    echo "  rn-dev <command>    # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  npx create-expo-app MyApp --template blank-typescript"
    echo "  cd MyApp && npm start"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';

  # Platform-specific environment variables
  ${lib.optionalString stdenv.isDarwin ''
  NIX_LDFLAGS = "-F${pkgs.darwin.apple_sdk.frameworks.CoreServices}/Library/Frameworks -framework CoreServices";
  ''}
}