<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Navigation -->
    <AppHeader />
    
    <!-- Main content -->
    <main class="flex-1">
      <router-view v-slot="{ Component, route }">
        <transition
          name="page"
          mode="out-in"
          appear
        >
          <component
            :is="Component"
            :key="route.path"
          />
        </transition>
      </router-view>
    </main>
    
    <!-- Footer -->
    <AppFooter />
    
    <!-- Global notifications -->
    <div
      v-if="notifications.length > 0"
      class="fixed top-4 right-4 z-50 space-y-2"
    >
      <transition-group
        name="notification"
        tag="div"
      >
        <div
          v-for="notification in notifications"
          :key="notification.id"
          :class="[
            'max-w-sm w-full bg-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5 overflow-hidden',
            {
              'border-l-4 border-green-400': notification.type === 'success',
              'border-l-4 border-red-400': notification.type === 'error',
              'border-l-4 border-yellow-400': notification.type === 'warning',
              'border-l-4 border-blue-400': notification.type === 'info',
            }
          ]"
        >
          <div class="p-4">
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <CheckCircleIcon
                  v-if="notification.type === 'success'"
                  class="h-6 w-6 text-green-400"
                />
                <XCircleIcon
                  v-else-if="notification.type === 'error'"
                  class="h-6 w-6 text-red-400"
                />
                <ExclamationTriangleIcon
                  v-else-if="notification.type === 'warning'"
                  class="h-6 w-6 text-yellow-400"
                />
                <InformationCircleIcon
                  v-else
                  class="h-6 w-6 text-blue-400"
                />
              </div>
              <div class="ml-3 w-0 flex-1 pt-0.5">
                <p class="text-sm font-medium text-gray-900">
                  {{ notification.title }}
                </p>
                <p
                  v-if="notification.message"
                  class="mt-1 text-sm text-gray-500"
                >
                  {{ notification.message }}
                </p>
              </div>
              <div class="ml-4 flex-shrink-0 flex">
                <button
                  class="bg-white rounded-md inline-flex text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  @click="removeNotification(notification.id)"
                >
                  <span class="sr-only">Close</span>
                  <XMarkIcon class="h-5 w-5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </transition-group>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import {
    CheckCircleIcon,
    XCircleIcon,
    ExclamationTriangleIcon,
    InformationCircleIcon,
    XMarkIcon,
  } from '@heroicons/vue/24/outline'
  
  import AppHeader from '@/components/AppHeader.vue'
  import AppFooter from '@/components/AppFooter.vue'
  import { useNotificationStore } from '@/stores/notification'
  
  const notificationStore = useNotificationStore()
  const { notifications } = storeToRefs(notificationStore)
  const { removeNotification } = notificationStore
</script>

<style scoped>
  /* Page transitions */
  .page-enter-active,
  .page-leave-active {
    transition: opacity 0.3s ease, transform 0.3s ease;
  }
  
  .page-enter-from {
    opacity: 0;
    transform: translateX(10px);
  }
  
  .page-leave-to {
    opacity: 0;
    transform: translateX(-10px);
  }
  
  /* Notification transitions */
  .notification-enter-active {
    transition: all 0.3s ease;
  }
  
  .notification-leave-active {
    transition: all 0.3s ease;
  }
  
  .notification-enter-from {
    transform: translateX(100%);
    opacity: 0;
  }
  
  .notification-leave-to {
    transform: translateX(100%);
    opacity: 0;
  }
  
  .notification-move {
    transition: transform 0.3s ease;
  }
</style>