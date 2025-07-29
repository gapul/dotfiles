# React Native Mobile Application Template
# Modern cross-platform mobile development with Expo and TypeScript

{ lib, pkgs, ... }:

{
  name = "react-native-mobile";
  description = "React Native mobile application with Expo, TypeScript, and modern tooling";
  
  # Template metadata
  template = {
    category = "mobile";
    tags = [ "react-native" "expo" "typescript" "mobile" "ios" "android" ];
    language = "typescript";
    framework = "react-native";
  };

  # Dependencies and tools
  dependencies = with pkgs; [
    # Node.js ecosystem
    nodejs_20
    yarn
    
    # Mobile development
    android-studio
    watchman
    
    # iOS development (macOS only)
    (lib.optionals stdenv.isDarwin [
      cocoapods
    ])
    
    # Development tools
    git
    jq
    curl
    
    # Testing and debugging
    flipper
  ];

  # Development environment
  environment = {
    EXPO_CLI_VERSION = "latest";
    REACT_NATIVE_VERSION = "0.72.x";
    NODE_ENV = "development";
    FLIPPER_DISABLE_PLUGIN_AUTO_UPDATE = "1";
  };

  # Setup scripts
  scripts = {
    init = ''
      echo "🚀 Initializing React Native project..."
      
      # Install Expo CLI globally if not present
      if ! command -v expo &> /dev/null; then
        npm install -g @expo/cli@latest
      fi
      
      # Create Expo project
      npx create-expo-app@latest . --template blank-typescript
      
      # Install additional dependencies
      npm install @react-navigation/native @react-navigation/stack @react-navigation/bottom-tabs
      npm install react-native-screens react-native-safe-area-context
      npm install @reduxjs/toolkit react-redux
      npm install react-hook-form @hookform/resolvers zod
      npm install react-native-paper react-native-vector-icons
      npm install @react-native-async-storage/async-storage
      npm install expo-secure-store expo-constants expo-updates
      npm install expo-camera expo-image-picker expo-location
      npm install axios react-query
      
      # Development dependencies
      npm install -D @types/react @types/react-native
      npm install -D eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin
      npm install -D prettier eslint-config-prettier eslint-plugin-prettier
      npm install -D @testing-library/react-native @testing-library/jest-native
      npm install -D jest-expo detox
      
      echo "✅ React Native project initialized successfully!"
      echo "📱 To start development:"
      echo "  npm run ios     # Run on iOS simulator"
      echo "  npm run android # Run on Android emulator"
      echo "  npm run web     # Run on web browser"
    '';

    dev = ''
      echo "🔥 Starting Expo development server..."
      npm start
    '';

    ios = ''
      echo "📱 Starting iOS simulator..."
      npm run ios
    '';

    android = ''
      echo "🤖 Starting Android emulator..."
      npm run android
    '';

    web = ''
      echo "🌐 Starting web development..."
      npm run web
    '';

    build = ''
      echo "🏗️ Building for production..."
      eas build --platform all
    '';

    test = ''
      echo "🧪 Running tests..."
      npm test
    '';

    lint = ''
      echo "🔍 Running linter..."
      npm run lint
    '';

    format = ''
      echo "💅 Formatting code..."
      npm run format
    '';
  };

  # File templates
  files = {
    "package.json" = ./package.json;
    "tsconfig.json" = ./tsconfig.json;
    "babel.config.js" = ./babel.config.js;
    "metro.config.js" = ./metro.config.js;
    "app.config.ts" = ./app.config.ts;
    ".eslintrc.js" = ./.eslintrc.js;
    ".prettierrc" = ./.prettierrc;
    "eas.json" = ./eas.json;
    "App.tsx" = ./App.tsx;
    "src/" = ./src;
    "assets/" = ./assets;
    "__tests__/" = ./__tests__;
    ".gitignore" = ./.gitignore;
    "README.md" = ./README.md;
  };

  # Post-setup hooks
  postSetup = ''
    echo "🎉 React Native template setup complete!"
    echo ""
    echo "📂 Project structure:"
    echo "  src/               # Source code"
    echo "  src/components/    # Reusable components"
    echo "  src/screens/       # Screen components"
    echo "  src/navigation/    # Navigation setup"
    echo "  src/store/         # Redux store"
    echo "  src/services/      # API services"
    echo "  src/utils/         # Utility functions"
    echo "  src/types/         # TypeScript types"
    echo "  assets/            # Images, fonts, etc."
    echo ""
    echo "🛠️ Available commands:"
    echo "  npm start          # Start Expo dev server"
    echo "  npm run ios        # Run on iOS"
    echo "  npm run android    # Run on Android"
    echo "  npm run web        # Run on web"
    echo "  npm test           # Run tests"
    echo "  npm run lint       # Run ESLint"
    echo "  npm run format     # Format with Prettier"
    echo ""
    echo "📚 Next steps:"
    echo "  1. Set up development environment (Xcode, Android Studio)"
    echo "  2. Configure device/simulator"
    echo "  3. Start developing with 'npm start'"
    echo "  4. Install Expo Go app for testing on physical devices"
  '';
}