import { createApp } from 'vue'
import { createPinia } from 'pinia'
import router from './router'
import App from './App.vue'

// Import global CSS
import '@/assets/css/main.css'

// Create Vue app
const app = createApp(App)

// Install plugins
app.use(createPinia())
app.use(router)

// Global error handler
app.config.errorHandler = (err, vm, info) => {
  console.error('Global error:', err)
  console.error('Component:', vm)
  console.error('Error info:', info)
  
  // You can integrate with error reporting service here
  // e.g., Sentry, LogRocket, etc.
}

// Global warning handler
app.config.warnHandler = (msg, vm, trace) => {
  console.warn('Global warning:', msg)
  console.warn('Component:', vm)
  console.warn('Trace:', trace)
}

// Mount the app
app.mount('#app')