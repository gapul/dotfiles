import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { User, LoginCredentials, RegisterData } from '@/types'
import { api } from '@/utils/api'
import { useNotificationStore } from './notification'

export const useAuthStore = defineStore('auth', () => {
  // State
  const user = ref<User | null>(null)
  const token = ref<string | null>(null)
  const isLoading = ref(false)
  const isInitialized = ref(false)

  // Getters
  const isAuthenticated = computed(() => !!user.value && !!token.value)
  const userRole = computed(() => user.value?.role || 'guest')
  const isAdmin = computed(() => userRole.value === 'admin')

  // Actions
  async function login(credentials: LoginCredentials): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      const response = await api.post('/auth/login', credentials)
      const { user: userData, token: userToken } = response.data.data
      
      // Store user data and token
      user.value = userData
      token.value = userToken
      
      // Persist to localStorage
      localStorage.setItem('auth_token', userToken)
      localStorage.setItem('auth_user', JSON.stringify(userData))
      
      // Set token in API headers
      api.defaults.headers.common['Authorization'] = `Bearer ${userToken}`
      
      notificationStore.addNotification({
        type: 'success',
        title: 'Login successful',
        message: `Welcome back, ${userData.name}!`,
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Login failed'
      notificationStore.addNotification({
        type: 'error',
        title: 'Login failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function register(userData: RegisterData): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      const response = await api.post('/auth/register', userData)
      const { user: newUser, token: userToken } = response.data.data
      
      // Store user data and token
      user.value = newUser
      token.value = userToken
      
      // Persist to localStorage
      localStorage.setItem('auth_token', userToken)
      localStorage.setItem('auth_user', JSON.stringify(newUser))
      
      // Set token in API headers
      api.defaults.headers.common['Authorization'] = `Bearer ${userToken}`
      
      notificationStore.addNotification({
        type: 'success',
        title: 'Registration successful',
        message: `Welcome to {{PROJECT_NAME}}, ${newUser.name}!`,
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Registration failed'
      notificationStore.addNotification({
        type: 'error',
        title: 'Registration failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function logout(): Promise<void> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      // Call logout endpoint if token exists
      if (token.value) {
        await api.post('/auth/logout')
      }
    } catch (error) {
      console.error('Logout API call failed:', error)
    } finally {
      // Clear local state regardless of API call result
      user.value = null
      token.value = null
      
      // Clear localStorage
      localStorage.removeItem('auth_token')
      localStorage.removeItem('auth_user')
      
      // Remove token from API headers
      delete api.defaults.headers.common['Authorization']
      
      notificationStore.addNotification({
        type: 'info',
        title: 'Logged out',
        message: 'You have been successfully logged out.',
      })
      
      isLoading.value = false
    }
  }

  async function getCurrentUser(): Promise<boolean> {
    if (!token.value) {
      return false
    }
    
    try {
      const response = await api.get('/auth/me')
      user.value = response.data.data
      return true
    } catch (error) {
      console.error('Failed to get current user:', error)
      // Clear invalid token
      await logout()
      return false
    }
  }

  async function updateProfile(profileData: Partial<User>): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    if (!user.value) {
      return false
    }
    
    try {
      isLoading.value = true
      
      const response = await api.put(`/users/${user.value.id}/profile`, profileData)
      user.value = { ...user.value, ...response.data.data }
      
      // Update localStorage
      localStorage.setItem('auth_user', JSON.stringify(user.value))
      
      notificationStore.addNotification({
        type: 'success',
        title: 'Profile updated',
        message: 'Your profile has been successfully updated.',
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to update profile'
      notificationStore.addNotification({
        type: 'error',
        title: 'Update failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function changePassword(passwordData: {
    currentPassword: string
    newPassword: string
    confirmPassword: string
  }): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      await api.put('/auth/change-password', passwordData)
      
      notificationStore.addNotification({
        type: 'success',
        title: 'Password changed',
        message: 'Your password has been successfully updated.',
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to change password'
      notificationStore.addNotification({
        type: 'error',
        title: 'Password change failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function initializeAuth(): Promise<void> {
    if (isInitialized.value) {
      return
    }
    
    try {
      const storedToken = localStorage.getItem('auth_token')
      const storedUser = localStorage.getItem('auth_user')
      
      if (storedToken && storedUser) {
        token.value = storedToken
        user.value = JSON.parse(storedUser)
        
        // Set token in API headers
        api.defaults.headers.common['Authorization'] = `Bearer ${storedToken}`
        
        // Validate token by fetching current user
        const isValid = await getCurrentUser()
        
        if (!isValid) {
          // Token is invalid, clear everything
          user.value = null
          token.value = null
          localStorage.removeItem('auth_token')
          localStorage.removeItem('auth_user')
          delete api.defaults.headers.common['Authorization']
        }
      }
    } catch (error) {
      console.error('Failed to initialize auth:', error)
      // Clear potentially corrupted data
      user.value = null
      token.value = null
      localStorage.removeItem('auth_token')
      localStorage.removeItem('auth_user')
      delete api.defaults.headers.common['Authorization']
    } finally {
      isInitialized.value = true
    }
  }

  async function refreshToken(): Promise<boolean> {
    try {
      const refreshToken = localStorage.getItem('refresh_token')
      if (!refreshToken) {
        return false
      }
      
      const response = await api.post('/auth/refresh', { refreshToken })
      const { user: userData, token: newToken } = response.data.data
      
      user.value = userData
      token.value = newToken
      
      localStorage.setItem('auth_token', newToken)
      localStorage.setItem('auth_user', JSON.stringify(userData))
      
      api.defaults.headers.common['Authorization'] = `Bearer ${newToken}`
      
      return true
    } catch (error) {
      console.error('Token refresh failed:', error)
      await logout()
      return false
    }
  }

  return {
    // State
    user,
    token,
    isLoading,
    isInitialized,
    
    // Getters
    isAuthenticated,
    userRole,
    isAdmin,
    
    // Actions
    login,
    register,
    logout,
    getCurrentUser,
    updateProfile,
    changePassword,
    initializeAuth,
    refreshToken,
  }
})