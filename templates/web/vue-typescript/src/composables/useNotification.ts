import { storeToRefs } from 'pinia'
import { useNotificationStore } from '@/stores/notification'
import type { Notification } from '@/stores/notification'

export function useNotification() {
  const notificationStore = useNotificationStore()
  const { notifications } = storeToRefs(notificationStore)

  // Create notification with auto-dismiss
  function notify(
    type: Notification['type'],
    title: string,
    message?: string,
    options: {
      duration?: number
      persistent?: boolean
      actions?: Array<{
        label: string
        action: () => void
        style?: 'primary' | 'secondary'
      }>
    } = {}
  ): string {
    return notificationStore.addNotification({
      type,
      title,
      message,
      ...options,
    })
  }

  // Convenience methods
  function success(title: string, message?: string, duration?: number): string {
    return notificationStore.success(title, message, duration)
  }

  function error(title: string, message?: string, persistent = false): string {
    return notificationStore.error(title, message, persistent)
  }

  function warning(title: string, message?: string, duration?: number): string {
    return notificationStore.warning(title, message, duration)
  }

  function info(title: string, message?: string, duration?: number): string {
    return notificationStore.info(title, message, duration)
  }

  // Advanced notification methods
  function confirmAction(
    title: string,
    message: string,
    onConfirm: () => void,
    onCancel?: () => void
  ): string {
    return notificationStore.addNotification({
      type: 'warning',
      title,
      message,
      persistent: true,
      actions: [
        {
          label: 'Confirm',
          action: () => {
            onConfirm()
            notificationStore.removeNotification(id)
          },
          style: 'primary',
        },
        {
          label: 'Cancel',
          action: () => {
            onCancel?.()
            notificationStore.removeNotification(id)
          },
          style: 'secondary',
        },
      ],
    })
  }

  function loadingNotification(title: string, message?: string): {
    id: string
    dismiss: () => void
    success: (successTitle: string, successMessage?: string) => void
    error: (errorTitle: string, errorMessage?: string) => void
  } {
    const id = notificationStore.addNotification({
      type: 'info',
      title,
      message,
      persistent: true,
    })

    return {
      id,
      dismiss: () => notificationStore.removeNotification(id),
      success: (successTitle: string, successMessage?: string) => {
        notificationStore.removeNotification(id)
        success(successTitle, successMessage)
      },
      error: (errorTitle: string, errorMessage?: string) => {
        notificationStore.removeNotification(id)
        error(errorTitle, errorMessage)
      },
    }
  }

  // API response handlers
  function handleApiSuccess(
    response: any,
    defaultTitle = 'Success',
    defaultMessage?: string
  ): void {
    const title = response.message || defaultTitle
    const message = defaultMessage
    success(title, message)
  }

  function handleApiError(
    error: any,
    defaultTitle = 'Error',
    defaultMessage?: string
  ): void {
    const title = error.response?.data?.message || error.message || defaultTitle
    const message = defaultMessage || 'Please try again later'
    error(title, message)
  }

  // Form validation error display
  function displayValidationErrors(errors: Record<string, string>): void {
    const errorList = Object.entries(errors)
      .map(([field, message]) => `${field}: ${message}`)
      .join('\n')

    error('Validation Error', errorList, true)
  }

  // Bulk operations feedback
  function bulkOperationFeedback(
    operation: string,
    total: number,
    successful: number,
    failed: number
  ): void {
    if (failed === 0) {
      success(
        'Operation Completed',
        `${operation} completed successfully for all ${total} items.`
      )
    } else if (successful === 0) {
      error(
        'Operation Failed',
        `${operation} failed for all ${total} items.`,
        true
      )
    } else {
      warning(
        'Partial Success',
        `${operation} completed for ${successful} items, failed for ${failed} items.`,
        8000
      )
    }
  }

  // Progress notifications
  function createProgressNotification(title: string): {
    id: string
    updateProgress: (progress: number, message?: string) => void
    complete: (successTitle?: string, successMessage?: string) => void
    fail: (errorTitle?: string, errorMessage?: string) => void
  } {
    let currentId = notificationStore.addNotification({
      type: 'info',
      title,
      message: 'Starting...',
      persistent: true,
    })

    return {
      id: currentId,
      updateProgress: (progress: number, message?: string) => {
        notificationStore.removeNotification(currentId)
        currentId = notificationStore.addNotification({
          type: 'info',
          title,
          message: message || `Progress: ${progress}%`,
          persistent: true,
        })
      },
      complete: (successTitle?: string, successMessage?: string) => {
        notificationStore.removeNotification(currentId)
        success(successTitle || 'Completed', successMessage)
      },
      fail: (errorTitle?: string, errorMessage?: string) => {
        notificationStore.removeNotification(currentId)
        error(errorTitle || 'Failed', errorMessage)
      },
    }
  }

  return {
    // State
    notifications,
    
    // Basic methods
    notify,
    success,
    error,
    warning,
    info,
    
    // Advanced methods
    confirmAction,
    loadingNotification,
    
    // API helpers
    handleApiSuccess,
    handleApiError,
    displayValidationErrors,
    bulkOperationFeedback,
    
    // Progress tracking
    createProgressNotification,
    
    // Store methods
    remove: notificationStore.removeNotification,
    clear: notificationStore.clearAllNotifications,
  }
}