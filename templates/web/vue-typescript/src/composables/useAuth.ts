import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import type { LoginCredentials, RegisterData, User } from '@/types'

export function useAuth() {
  const router = useRouter()
  const authStore = useAuthStore()

  // Reactive state from store
  const {
    user,
    token,
    isLoading,
    isInitialized,
    isAuthenticated,
    userRole,
    isAdmin,
  } = storeToRefs(authStore)

  // Computed properties
  const canAccessAdmin = computed(() => isAdmin.value)
  const displayName = computed(() => user.value?.name || 'User')
  const userInitials = computed(() => {
    if (!user.value?.name) return 'U'
    return user.value.name
      .split(' ')
      .map(part => part[0])
      .join('')
      .toUpperCase()
      .slice(0, 2)
  })

  // Auth actions
  async function login(credentials: LoginCredentials, redirectTo?: string): Promise<boolean> {
    const success = await authStore.login(credentials)
    
    if (success) {
      // Redirect after successful login
      const redirect = redirectTo || router.currentRoute.value.query.redirect as string || '/dashboard'
      await router.push(redirect)
    }
    
    return success
  }

  async function register(userData: RegisterData, redirectTo?: string): Promise<boolean> {
    const success = await authStore.register(userData)
    
    if (success) {
      // Redirect after successful registration
      const redirect = redirectTo || '/dashboard'
      await router.push(redirect)
    }
    
    return success
  }

  async function logout(redirectTo?: string): Promise<void> {
    await authStore.logout()
    
    // Redirect after logout
    const redirect = redirectTo || '/login'
    await router.push(redirect)
  }

  async function updateProfile(profileData: Partial<User>): Promise<boolean> {
    return authStore.updateProfile(profileData)
  }

  async function changePassword(passwordData: {
    currentPassword: string
    newPassword: string
    confirmPassword: string
  }): Promise<boolean> {
    return authStore.changePassword(passwordData)
  }

  // Permission helpers
  function hasRole(role: string): boolean {
    return userRole.value === role
  }

  function hasAnyRole(roles: string[]): boolean {
    return roles.includes(userRole.value)
  }

  function canAccess(requiredRoles?: string[]): boolean {
    if (!requiredRoles || requiredRoles.length === 0) {
      return true
    }
    
    if (!isAuthenticated.value) {
      return false
    }
    
    return hasAnyRole(requiredRoles)
  }

  // Navigation guards
  function requireAuth(): boolean {
    if (!isAuthenticated.value) {
      router.push({
        name: 'login',
        query: { redirect: router.currentRoute.value.fullPath },
      })
      return false
    }
    return true
  }

  function requireGuest(): boolean {
    if (isAuthenticated.value) {
      router.push('/dashboard')
      return false
    }
    return true
  }

  function requireRole(role: string): boolean {
    if (!requireAuth()) {
      return false
    }
    
    if (!hasRole(role)) {
      router.push('/unauthorized')
      return false
    }
    
    return true
  }

  function requireAdmin(): boolean {
    return requireRole('admin')
  }

  // Initialize auth on app start
  async function initialize(): Promise<void> {
    if (!isInitialized.value) {
      await authStore.initializeAuth()
    }
  }

  // Auto-refresh token before expiration
  function startTokenRefresh(): void {
    // Check token expiration every 5 minutes
    const interval = setInterval(async () => {
      if (isAuthenticated.value && token.value) {
        try {
          // Check if token expires in next 10 minutes
          const tokenPayload = JSON.parse(atob(token.value.split('.')[1]))
          const expiresAt = tokenPayload.exp * 1000
          const now = Date.now()
          const tenMinutes = 10 * 60 * 1000
          
          if (expiresAt - now < tenMinutes) {
            await authStore.refreshToken()
          }
        } catch (error) {
          console.error('Token refresh check failed:', error)
        }
      } else {
        // Clear interval if not authenticated
        clearInterval(interval)
      }
    }, 5 * 60 * 1000) // 5 minutes
  }

  return {
    // State
    user,
    token,
    isLoading,
    isInitialized,
    isAuthenticated,
    userRole,
    isAdmin,
    canAccessAdmin,
    displayName,
    userInitials,
    
    // Actions
    login,
    register,
    logout,
    updateProfile,
    changePassword,
    initialize,
    
    // Permission helpers
    hasRole,
    hasAnyRole,
    canAccess,
    
    // Navigation guards
    requireAuth,
    requireGuest,
    requireRole,
    requireAdmin,
    
    // Utilities
    startTokenRefresh,
  }
}