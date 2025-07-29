# Flutter Mobile Development Environment
# Complete setup for cross-platform mobile development with Flutter and Dart

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
    platformVersions = [ "34" "33" "32" "31" "30" ];
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
  ]);

  # Development scripts
  setupScript = pkgs.writeShellScriptBin "setup-flutter" ''
    set -e
    
    echo "🚀 Setting up Flutter development environment..."
    
    # Set Android environment variables
    export ANDROID_SDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export PATH="$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
    
    # Check Flutter installation
    echo "🔍 Checking Flutter installation..."
    flutter --version
    
    # Run Flutter doctor
    echo "🩺 Running Flutter doctor..."
    flutter doctor
    
    ${lib.optionalString stdenv.isDarwin ''
    # iOS setup (macOS only)
    echo "🍎 Checking iOS setup..."
    if command -v xcodebuild >/dev/null 2>&1; then
      xcodebuild -version
    else
      echo "⚠️  Xcode not found. Please install Xcode from the App Store."
    fi
    ''}
    
    echo ""
    echo "🎯 Quick start:"
    echo "  flutter create myapp"
    echo "  cd myapp"
    echo "  flutter run"
    echo ""
    echo "✅ Flutter environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "flutter-dev" ''
    case "$1" in
      create)
        echo "🆕 Creating new Flutter project..."
        flutter create "$2" --org com.example --platforms android,ios,web
        ;;
      run)
        echo "🚀 Running Flutter app..."
        flutter run
        ;;
      run:android)
        echo "🤖 Running on Android..."
        flutter run -d android
        ;;
      run:ios)
        echo "🍎 Running on iOS..."
        flutter run -d ios
        ;;
      run:web)
        echo "🌐 Running on web..."
        flutter run -d web-server --web-port 8080
        ;;
      build)
        echo "🏗️ Building Flutter app..."
        case "$2" in
          android)
            flutter build apk --release
            ;;
          ios)
            flutter build ios --release
            ;;
          web)
            flutter build web --release
            ;;
          *)
            echo "Specify platform: android, ios, or web"
            ;;
        esac
        ;;
      test)
        echo "🧪 Running tests..."
        flutter test
        ;;
      analyze)
        echo "🔍 Analyzing code..."
        flutter analyze
        ;;
      format)
        echo "💅 Formatting code..."
        dart format .
        ;;
      pub:get)
        echo "📦 Getting dependencies..."
        flutter pub get
        ;;
      pub:upgrade)
        echo "⬆️ Upgrading dependencies..."
        flutter pub upgrade
        ;;
      clean)
        echo "🧹 Cleaning project..."
        flutter clean
        flutter pub get
        ;;
      doctor)
        echo "🩺 Running Flutter doctor..."
        flutter doctor -v
        ;;
      devices)
        echo "📱 Listing devices..."
        flutter devices
        ;;
      emulators)
        echo "📱 Listing emulators..."
        flutter emulators
        ;;
      logs)
        echo "📋 Viewing logs..."
        flutter logs
        ;;
      *)
        echo "🐦 Flutter Development Commands"
        echo ""
        echo "Usage: flutter-dev <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <name>     Create new Flutter project"
        echo "  run               Run app on connected device"
        echo "  run:android       Run specifically on Android"
        echo "  run:ios           Run specifically on iOS"
        echo "  run:web           Run on web browser"
        echo "  build <platform>  Build for platform (android/ios/web)"
        echo "  test              Run tests"
        echo "  analyze           Analyze code"
        echo "  format            Format code"
        echo "  pub:get           Get dependencies"
        echo "  pub:upgrade       Upgrade dependencies"
        echo "  clean             Clean project"
        echo "  doctor            Run Flutter doctor"
        echo "  devices           List connected devices"
        echo "  emulators         List available emulators"
        echo "  logs              View logs"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "flutter-dev";
  
  buildInputs = with pkgs; [
    # Flutter and Dart
    flutter
    dart
    
    # Android development
    androidComposition.androidsdk
    openjdk17
    gradle
    
    # iOS development (macOS only)
  ] ++ iosDeps ++ [
    
    # Development tools
    git
    curl
    unzip
    which
    
    # Development utilities
    setupScript
    devScript
    
    # Additional tools
    rsync
  ];

  shellHook = ''
    # Android SDK environment
    export ANDROID_SDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_AVD_HOME="$HOME/.android/avd"
    export PATH="$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
    
    # Java environment for Android
    export JAVA_HOME="${pkgs.openjdk17}/lib/openjdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    
    # Flutter environment
    export FLUTTER_ROOT="${pkgs.flutter}"
    export PATH="$FLUTTER_ROOT/bin:$PATH"
    export PUB_CACHE="$HOME/.pub-cache"
    
    # Chrome for web development
    export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"
    
    ${lib.optionalString stdenv.isDarwin ''
    # iOS environment (macOS only)
    export IOS_SIMULATOR_UDID=""
    ''}
    
    # Performance settings
    export FLUTTER_WEB_USE_SKIA=true
    export FLUTTER_WEB_AUTO_DETECT=true
    
    echo "🐦 Flutter Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐦 Flutter: $(flutter --version | head -n1)"
    echo "🎯 Dart: $(dart --version)"
    echo "📱 Android SDK: $ANDROID_SDK_ROOT"
    echo "☕ Java: $JAVA_HOME"
    ${lib.optionalString stdenv.isDarwin ''
    echo "🍎 iOS tools: Available"
    ''}
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-flutter     # Initial environment setup"
    echo "  flutter-dev       # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  flutter-dev create myapp"
    echo "  cd myapp"
    echo "  flutter-dev run"
    echo ""
    echo "🧪 Testing:"
    echo "  flutter-dev test      # Run unit tests"
    echo "  flutter-dev analyze   # Static analysis"
    echo "  flutter-dev doctor    # Environment check"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}