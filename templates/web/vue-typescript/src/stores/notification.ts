import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface Notification {
  id: string
  type: 'success' | 'error' | 'warning' | 'info'
  title: string
  message?: string
  duration?: number
  persistent?: boolean
}

export const useNotificationStore = defineStore('notification', () => {
  // State
  const notifications = ref<Notification[]>([])

  // Actions
  function addNotification(notification: Omit<Notification, 'id'>): string {
    const id = `notification-${Date.now()}-${Math.random()}`
    const newNotification: Notification = {
      id,
      duration: 5000, // Default 5 seconds
      persistent: false,
      ...notification,
    }

    notifications.value.push(newNotification)

    // Auto-remove notification after duration (unless persistent)
    if (!newNotification.persistent && newNotification.duration) {
      setTimeout(() => {
        removeNotification(id)
      }, newNotification.duration)
    }

    return id
  }

  function removeNotification(id: string): void {
    const index = notifications.value.findIndex(n => n.id === id)
    if (index > -1) {
      notifications.value.splice(index, 1)
    }
  }

  function clearAllNotifications(): void {
    notifications.value = []
  }

  // Convenience methods for different notification types
  function success(title: string, message?: string, duration?: number): string {
    return addNotification({
      type: 'success',
      title,
      message,
      duration,
    })
  }

  function error(title: string, message?: string, persistent = false): string {
    return addNotification({
      type: 'error',
      title,
      message,
      persistent,
      duration: persistent ? undefined : 8000, // Longer duration for errors
    })
  }

  function warning(title: string, message?: string, duration?: number): string {
    return addNotification({
      type: 'warning',
      title,
      message,
      duration: duration || 6000,
    })
  }

  function info(title: string, message?: string, duration?: number): string {
    return addNotification({
      type: 'info',
      title,
      message,
      duration,
    })
  }

  return {
    // State
    notifications,
    
    // Actions
    addNotification,
    removeNotification,
    clearAllNotifications,
    success,
    error,
    warning,
    info,
  }
})