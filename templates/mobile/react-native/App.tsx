import React from 'react'
import { StatusBar } from 'expo-status-bar'
import { Provider as PaperProvider } from 'react-native-paper'
import { Provider as ReduxProvider } from 'react-redux'
import { PersistGate } from 'redux-persist/integration/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import Toast from 'react-native-toast-message'

import { store, persistor } from './src/store'
import { AppNavigator } from './src/navigation/AppNavigator'
import { theme } from './src/theme'
import { LoadingScreen } from './src/components/LoadingScreen'
import { toastConfig } from './src/utils/toast'

// Create a client for React Query
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      retry: 2,
    },
  },
})

export default function App() {
  return (
    <ReduxProvider store={store}>
      <PersistGate loading={<LoadingScreen />} persistor={persistor}>
        <QueryClientProvider client={queryClient}>
          <PaperProvider theme={theme}>
            <StatusBar style="auto" />
            <AppNavigator />
            <Toast config={toastConfig} />
          </PaperProvider>
        </QueryClientProvider>
      </PersistGate>
    </ReduxProvider>
  )
}