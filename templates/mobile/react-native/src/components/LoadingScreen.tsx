import React from 'react'
import { View, StyleSheet } from 'react-native'
import { ActivityIndicator, Text, useTheme } from 'react-native-paper'
import LottieView from 'lottie-react-native'

interface LoadingScreenProps {
  message?: string
  showLottie?: boolean
}

export function LoadingScreen({ message = 'Loading...', showLottie = true }: LoadingScreenProps) {
  const theme = useTheme()

  return (
    <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
      {showLottie ? (
        <LottieView
          source={require('../../assets/animations/loading.json')}
          autoPlay
          loop
          style={styles.lottie}
        />
      ) : (
        <ActivityIndicator size="large" color={theme.colors.primary} />
      )}
      <Text style={[styles.message, { color: theme.colors.onBackground }]}>
        {message}
      </Text>
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  lottie: {
    width: 200,
    height: 200,
  },
  message: {
    marginTop: 20,
    fontSize: 16,
    textAlign: 'center',
  },
})