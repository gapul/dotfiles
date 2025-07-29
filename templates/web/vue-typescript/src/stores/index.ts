// Export all stores from this index file for easy importing
export { useAuthStore } from './auth'
export { useUserStore } from './user'
export { useNotificationStore } from './notification'

// You can also create a store plugin here if needed
import type { App } from 'vue'
import { createPinia } from 'pinia'

export function setupStore(app: App) {
  const pinia = createPinia()
  
  // Add any pinia plugins here
  // pinia.use(somePlugin)
  
  app.use(pinia)
  return pinia
}