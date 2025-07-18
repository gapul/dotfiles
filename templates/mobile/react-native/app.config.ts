import { ExpoConfig, ConfigContext } from 'expo/config'

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: '{{PROJECT_NAME}}',
  slug: '{{PROJECT_NAME_SLUG}}',
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'automatic',
  splash: {
    image: './assets/splash.png',
    resizeMode: 'contain',
    backgroundColor: '#ffffff',
  },
  assetBundlePatterns: ['**/*'],
  ios: {
    supportsTablet: true,
    bundleIdentifier: 'com.{{ORGANIZATION}}.{{PROJECT_NAME_SLUG}}',
    buildNumber: '1',
    infoPlist: {
      NSCameraUsageDescription: 'This app uses the camera to take photos for your profile and posts.',
      NSPhotoLibraryUsageDescription: 'This app needs access to your photo library to select images.',
      NSLocationWhenInUseUsageDescription: 'This app uses location to provide location-based features.',
      NSMicrophoneUsageDescription: 'This app uses the microphone for video recording.',
    },
  },
  android: {
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#ffffff',
    },
    package: 'com.{{ORGANIZATION}}.{{PROJECT_NAME_SLUG}}',
    versionCode: 1,
    permissions: [
      'CAMERA',
      'RECORD_AUDIO',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'NOTIFICATIONS',
    ],
  },
  web: {
    favicon: './assets/favicon.png',
    bundler: 'metro',
  },
  plugins: [
    'expo-router',
    [
      'expo-camera',
      {
        cameraPermission: 'Allow {{PROJECT_NAME}} to access your camera.',
      },
    ],
    [
      'expo-image-picker',
      {
        photosPermission: 'The app accesses your photos to let you share them.',
      },
    ],
    [
      'expo-location',
      {
        locationAlwaysAndWhenInUsePermission: 'Allow {{PROJECT_NAME}} to use your location.',
      },
    ],
    [
      'expo-notifications',
      {
        icon: './assets/notification-icon.png',
        color: '#ffffff',
      },
    ],
  ],
  extra: {
    eas: {
      projectId: '{{EAS_PROJECT_ID}}',
    },
    apiUrl: process.env.EXPO_PUBLIC_API_URL || 'http://localhost:3000',
    environment: process.env.EXPO_PUBLIC_ENVIRONMENT || 'development',
  },
  updates: {
    fallbackToCacheTimeout: 0,
    url: 'https://u.expo.dev/{{EAS_PROJECT_ID}}',
  },
  runtimeVersion: {
    policy: 'sdkVersion',
  },
})