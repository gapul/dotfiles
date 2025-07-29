<template>
  <header class="bg-white shadow-sm border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between items-center h-16">
        <!-- Logo and brand -->
        <div class="flex items-center">
          <router-link
            to="/"
            class="flex items-center space-x-3"
          >
            <div class="h-8 w-8 bg-primary-600 rounded-lg flex items-center justify-center">
              <span class="text-white font-bold text-sm">{{PROJECT_NAME.charAt(0).toUpperCase()}}</span>
            </div>
            <span class="text-xl font-semibold text-gray-900">{{PROJECT_NAME}}</span>
          </router-link>
        </div>

        <!-- Navigation -->
        <nav class="hidden md:flex space-x-8">
          <router-link
            v-for="item in navigation"
            :key="item.name"
            :to="item.to"
            :class="[
              'px-3 py-2 rounded-md text-sm font-medium transition-colors duration-200',
              item.current
                ? 'bg-primary-100 text-primary-700'
                : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'
            ]"
          >
            {{ item.name }}
          </router-link>
        </nav>

        <!-- User menu -->
        <div class="flex items-center space-x-4">
          <!-- Notifications (if authenticated) -->
          <button
            v-if="isAuthenticated"
            class="p-2 text-gray-400 hover:text-gray-600 relative"
            @click="toggleNotifications"
          >
            <BellIcon class="h-6 w-6" />
            <span
              v-if="unreadCount > 0"
              class="absolute -top-1 -right-1 h-5 w-5 bg-red-500 text-white text-xs rounded-full flex items-center justify-center"
            >
              {{ unreadCount > 9 ? '9+' : unreadCount }}
            </span>
          </button>

          <!-- User menu -->
          <div
            v-if="isAuthenticated"
            class="relative"
          >
            <Menu
              as="div"
              class="relative"
            >
              <MenuButton
                class="flex items-center space-x-3 p-2 rounded-md hover:bg-gray-50 transition-colors duration-200"
              >
                <div class="h-8 w-8 bg-primary-600 rounded-full flex items-center justify-center">
                  <span class="text-white text-sm font-medium">{{ userInitials }}</span>
                </div>
                <div class="hidden md:block text-left">
                  <p class="text-sm font-medium text-gray-900">{{ displayName }}</p>
                  <p class="text-xs text-gray-500">{{ userRole }}</p>
                </div>
                <ChevronDownIcon class="h-4 w-4 text-gray-400" />
              </MenuButton>

              <transition
                enter-active-class="transition ease-out duration-200"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95"
              >
                <MenuItems
                  class="absolute right-0 z-10 mt-2 w-56 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none"
                >
                  <MenuItem
                    v-for="item in userMenuItems"
                    :key="item.name"
                    v-slot="{ active }"
                  >
                    <router-link
                      v-if="item.to"
                      :to="item.to"
                      :class="[
                        active ? 'bg-gray-100' : '',
                        'flex items-center px-4 py-2 text-sm text-gray-700'
                      ]"
                    >
                      <component
                        :is="item.icon"
                        class="mr-3 h-4 w-4"
                      />
                      {{ item.name }}
                    </router-link>
                    <button
                      v-else
                      :class="[
                        active ? 'bg-gray-100' : '',
                        'flex items-center w-full px-4 py-2 text-left text-sm text-gray-700'
                      ]"
                      @click="item.action"
                    >
                      <component
                        :is="item.icon"
                        class="mr-3 h-4 w-4"
                      />
                      {{ item.name }}
                    </button>
                  </MenuItem>
                </MenuItems>
              </transition>
            </Menu>
          </div>

          <!-- Login button (if not authenticated) -->
          <div
            v-else
            class="flex items-center space-x-4"
          >
            <router-link
              to="/login"
              class="text-gray-600 hover:text-gray-900 text-sm font-medium"
            >
              Sign in
            </router-link>
            <router-link
              to="/register"
              class="bg-primary-600 hover:bg-primary-700 text-white px-4 py-2 rounded-md text-sm font-medium transition-colors duration-200"
            >
              Sign up
            </router-link>
          </div>

          <!-- Mobile menu button -->
          <button
            class="md:hidden p-2 text-gray-400 hover:text-gray-600"
            @click="toggleMobileMenu"
          >
            <Bars3Icon
              v-if="!showMobileMenu"
              class="h-6 w-6"
            />
            <XMarkIcon
              v-else
              class="h-6 w-6"
            />
          </button>
        </div>
      </div>

      <!-- Mobile menu -->
      <div
        v-if="showMobileMenu"
        class="md:hidden border-t border-gray-200 py-4"
      >
        <div class="space-y-1">
          <router-link
            v-for="item in navigation"
            :key="item.name"
            :to="item.to"
            :class="[
              'block px-3 py-2 rounded-md text-base font-medium',
              item.current
                ? 'bg-primary-100 text-primary-700'
                : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'
            ]"
            @click="showMobileMenu = false"
          >
            {{ item.name }}
          </router-link>
        </div>

        <!-- Mobile user menu -->
        <div
          v-if="isAuthenticated"
          class="mt-4 pt-4 border-t border-gray-200"
        >
          <div class="flex items-center space-x-3 px-3 py-2">
            <div class="h-10 w-10 bg-primary-600 rounded-full flex items-center justify-center">
              <span class="text-white font-medium">{{ userInitials }}</span>
            </div>
            <div>
              <p class="text-base font-medium text-gray-900">{{ displayName }}</p>
              <p class="text-sm text-gray-500">{{ userRole }}</p>
            </div>
          </div>
          <div class="mt-3 space-y-1">
            <router-link
              v-for="item in userMenuItems.filter(item => item.to)"
              :key="item.name"
              :to="item.to"
              class="flex items-center px-3 py-2 text-base font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-50 rounded-md"
              @click="showMobileMenu = false"
            >
              <component
                :is="item.icon"
                class="mr-3 h-5 w-5"
              />
              {{ item.name }}
            </router-link>
            <button
              v-for="item in userMenuItems.filter(item => !item.to)"
              :key="item.name"
              class="flex items-center w-full px-3 py-2 text-left text-base font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-50 rounded-md"
              @click="item.action(); showMobileMenu = false"
            >
              <component
                :is="item.icon"
                class="mr-3 h-5 w-5"
              />
              {{ item.name }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </header>
</template>

<script setup lang="ts">
  import { ref, computed } from 'vue'
  import { useRoute } from 'vue-router'
  import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue'
  import {
    BellIcon,
    Bars3Icon,
    XMarkIcon,
    ChevronDownIcon,
    UserIcon,
    Cog6ToothIcon,
    ArrowRightOnRectangleIcon,
  } from '@heroicons/vue/24/outline'
  
  import { useAuth } from '@/composables/useAuth'
  import type { NavigationItem } from '@/types'
  
  const route = useRoute()
  const { isAuthenticated, displayName, userRole, userInitials, logout } = useAuth()
  
  // Mobile menu state
  const showMobileMenu = ref(false)
  const showNotifications = ref(false)
  
  // Mock unread notifications count
  const unreadCount = ref(3)
  
  // Navigation items
  const navigation = computed<NavigationItem[]>(() => [
    {
      name: 'Home',
      to: '/',
      current: route.name === 'home',
    },
    {
      name: 'About',
      to: '/about',
      current: route.name === 'about',
    },
    ...(isAuthenticated.value
      ? [
          {
            name: 'Dashboard',
            to: '/dashboard',
            current: route.name === 'dashboard',
          },
        ]
      : []),
  ])
  
  // User menu items
  const userMenuItems = computed(() => [
    {
      name: 'Profile',
      to: '/profile',
      icon: UserIcon,
    },
    {
      name: 'Settings',
      to: '/settings',
      icon: Cog6ToothIcon,
    },
    {
      name: 'Sign out',
      action: () => logout(),
      icon: ArrowRightOnRectangleIcon,
    },
  ])
  
  function toggleMobileMenu(): void {
    showMobileMenu.value = !showMobileMenu.value
  }
  
  function toggleNotifications(): void {
    showNotifications.value = !showNotifications.value
  }
</script>