import React, { useEffect } from 'react'
import { NavigationContainer } from '@react-navigation/native'
import { createStackNavigator } from '@react-navigation/stack'
import { useSelector } from 'react-redux'

import { RootState } from '../store'
import { AuthNavigator } from './AuthNavigator'
import { MainNavigator } from './MainNavigator'
import { LoadingScreen } from '../components/LoadingScreen'
import { useAuth } from '../hooks/useAuth'

export type RootStackParamList = {
  Auth: undefined
  Main: undefined
}

const Stack = createStackNavigator<RootStackParamList>()

export function AppNavigator() {
  const { isLoading } = useSelector((state: RootState) => state.auth)
  const { checkAuthStatus } = useAuth()

  useEffect(() => {
    checkAuthStatus()
  }, [checkAuthStatus])

  if (isLoading) {
    return <LoadingScreen />
  }

  return (
    <NavigationContainer>
      <Stack.Navigator
        screenOptions={{
          headerShown: false,
          cardStyle: { backgroundColor: 'transparent' },
        }}
      >
        <Stack.Screen name="Auth" component={AuthNavigator} />
        <Stack.Screen name="Main" component={MainNavigator} />
      </Stack.Navigator>
    </NavigationContainer>
  )
}